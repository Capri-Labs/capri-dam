require 'rails_helper'

RSpec.describe WorkflowActionExecutor do
  let(:user)     { create(:user) }
  let(:asset)    { create(:asset, user: user, status: 'in_review') }
  let(:workflow) { create(:workflow) }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  def build_step(node_type, config = {})
    create(:workflow_step,
           workflow:      workflow,
           step_type:     'automated_action',
           node_type:     node_type,
           assignee_type: 'system',
           assignee_id:   0,
           step_config:   config)
  end

  # ── Asset operations ─────────────────────────────────────────────────────────

  describe 'asset operations' do
    it 'set_status updates the asset status' do
      step = build_step('set_status', { 'status' => 'approved' })
      described_class.new(instance, step).call
      expect(asset.reload.read_attribute_before_type_cast('status')).to eq(Asset.statuses['approved'].to_s)
    end

    it 'add_tags appends tags to asset properties' do
      step = build_step('add_tags', { 'tags' => 'hero, campaign' })
      described_class.new(instance, step).call
      expect(asset.reload.properties['tags']).to include('hero', 'campaign')
    end

    it 'remove_tags removes tags from asset properties' do
      asset.update!(properties: asset.properties.merge('tags' => %w[hero keep]))
      step = build_step('remove_tags', { 'tags' => 'hero' })
      described_class.new(instance, step).call
      expect(asset.reload.properties['tags']).to eq(%w[keep])
    end

    it 'archive soft-deletes the asset' do
      step = build_step('archive')
      described_class.new(instance, step).call
      expect(asset.reload.deleted_at).to be_present
    end

    it 'publish sets asset status to approved' do
      step = build_step('publish', { 'cdnSync' => false })
      described_class.new(instance, step).call
      expect(asset.reload.read_attribute_before_type_cast('status')).to eq(Asset.statuses['approved'].to_s)
    end

    it 'update_metadata writes a property with token substitution (legacy single pair)' do
      step = build_step('update_metadata', { 'metadataKey' => 'campaign', 'metadataValue' => 'Asset {{asset.id}}' })
      described_class.new(instance, step).call
      expect(asset.reload.properties['campaign']).to eq("Asset #{asset.id}")
    end

    it 'update_metadata handles multi-pair format' do
      step = build_step('update_metadata', {
        'pairs' => [
          { 'key' => 'dam:author', 'value' => 'Marketing' },
          { 'key' => 'dam:title',  'value' => '{{asset.title}}' },
        ],
      })
      described_class.new(instance, step).call
      props = asset.reload.properties
      expect(props['dam:author']).to eq('Marketing')
      expect(props['dam:title']).to eq(asset.title)
    end

    it 'move_asset updates the asset folder' do
      folder = create(:folder)
      step = build_step('move_asset', { 'folder' => folder.id.to_s })
      described_class.new(instance, step).call
      expect(asset.reload.folder_id).to eq(folder.id)
    end
  end

  # ── Notifications ─────────────────────────────────────────────────────────

  describe 'notifications' do
    it 'in_app_notification creates a Notification for the uploader' do
      step = build_step('in_app_notification', { 'recipient' => 'uploader', 'message' => 'Review {{asset.title}}' })
      expect { described_class.new(instance, step).call }.to change(Notification, :count).by(1)
      note = Notification.last
      expect(note.user).to eq(user)
      expect(note.message).to include(asset.title)
    end

    it 'email_notification creates an in-app Notification and does not raise' do
      step = build_step('email_notification', { 'recipient' => 'assignee', 'subject' => 'Review needed', 'body' => 'Hello {{asset.title}}' })
      expect { described_class.new(instance, step).call }.to change(Notification, :count).by(1)
    end

    it 'sms delegates to WorkflowSmsWorker when available' do
      allow(WorkflowSmsWorker).to receive(:perform_async)
      step = build_step('sms', { 'phone' => '+15550001234', 'message' => 'Check {{asset.title}}' })
      described_class.new(instance, step).call
      expect(WorkflowSmsWorker).to have_received(:perform_async)
        .with(instance.id, '+15550001234', a_string_including(asset.title))
    end
  end

  # ── Flow control ─────────────────────────────────────────────────────────

  describe 'flow control' do
    it 'condition returns :true_branch when the comparison matches' do
      asset.update!(properties: asset.properties.merge('content_type' => 'image/png'))
      step = build_step('condition', { 'field' => 'properties.content_type', 'operator' => 'equals', 'value' => 'image/png' })
      expect(described_class.new(instance, step).call).to eq(:true_branch)
    end

    it 'condition returns :false_branch when the comparison fails' do
      asset.update!(properties: asset.properties.merge('content_type' => 'image/png'))
      step = build_step('condition', { 'field' => 'properties.content_type', 'operator' => 'equals', 'value' => 'video/mp4' })
      expect(described_class.new(instance, step).call).to eq(:false_branch)
    end

    it 'condition supports starts_with operator' do
      asset.update!(properties: asset.properties.merge('mime' => 'image/jpeg'))
      step = build_step('condition', { 'field' => 'properties.mime', 'operator' => 'starts_with', 'value' => 'image/' })
      expect(described_class.new(instance, step).call).to eq(:true_branch)
    end

    it 'condition supports less_than operator' do
      asset.update!(properties: asset.properties.merge('size_mb' => '5'))
      step = build_step('condition', { 'field' => 'properties.size_mb', 'operator' => 'less_than', 'value' => '10' })
      expect(described_class.new(instance, step).call).to eq(:true_branch)
    end

    it 'delay enqueues WorkflowDelayWorker with correct duration and returns :delay_scheduled' do
      allow(WorkflowDelayWorker).to receive(:perform_in)
      step = build_step('delay', { 'delayValue' => 2, 'delayUnit' => 'hours' })
      result = described_class.new(instance, step).call
      expect(result).to eq(:delay_scheduled)
      expect(WorkflowDelayWorker).to have_received(:perform_in).with(7200, instance.id, step.id)
    end

    it 'delay converts days to seconds correctly' do
      allow(WorkflowDelayWorker).to receive(:perform_in)
      step = build_step('delay', { 'delayValue' => 1, 'delayUnit' => 'days' })
      described_class.new(instance, step).call
      expect(WorkflowDelayWorker).to have_received(:perform_in).with(86_400, instance.id, step.id)
    end
  end

  # ── Integrations ─────────────────────────────────────────────────────────

  describe 'integrations' do
    let(:conn) { instance_double(Faraday::Connection) }

    before do
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:run_request)
    end

    it 'webhook posts a JSON payload via Faraday' do
      expect(conn).to receive(:run_request)
        .with(:post, 'https://hooks.example.com/dam', anything, hash_including('Content-Type' => 'application/json'))

      step = build_step('webhook', { 'url' => 'https://hooks.example.com/dam', 'method' => 'POST' })
      described_class.new(instance, step).call
    end

    it 'secure_webhook adds an HMAC signature header' do
      expect(conn).to receive(:run_request)
        .with(:post, 'https://hooks.example.com/secure', anything, hash_including('X-Signature-SHA256' => /\A[0-9a-f]{64}\z/))

      step = build_step('secure_webhook', { 'url' => 'https://hooks.example.com/secure', 'authType' => 'hmac', 'secret' => 's3cr3t' })
      described_class.new(instance, step).call
    end

    it 'secure_webhook adds a bearer token header' do
      expect(conn).to receive(:run_request)
        .with(:post, anything, anything, hash_including('Authorization' => 'Bearer mytoken'))

      step = build_step('secure_webhook', { 'url' => 'https://hooks.example.com/bearer', 'authType' => 'bearer', 'secret' => 'mytoken' })
      described_class.new(instance, step).call
    end

    it 'slack posts with attachment color' do
      expect(conn).to receive(:run_request)
        .with(:post, 'https://hooks.slack.com/test', anything, anything)

      step = build_step('slack', { 'channel' => 'https://hooks.slack.com/test', 'message' => 'Hello', 'color' => 'warning' })
      described_class.new(instance, step).call
    end

    it 'api_call uses a configurable HTTP method' do
      expect(conn).to receive(:run_request)
        .with(:put, 'https://api.example.com/update', anything, anything)

      step = build_step('api_call', { 'url' => 'https://api.example.com/update', 'method' => 'PUT' })
      described_class.new(instance, step).call
    end
  end

  # ── AI & processing ──────────────────────────────────────────────────────

  describe 'AI & processing' do
    it 'ai_metadata enqueues an AiBatchJob when defined' do
      allow(AiBatchJobWorker).to receive(:perform_async)
      step = build_step('ai_metadata', { 'aiTask' => 'seo_enrichment' })
      described_class.new(instance, step).call
      expect(AiBatchJob.last.task_type).to eq('seo_enrichment')
    end

    it 'cdn_sync enqueues EdgeMetadataSyncWorker when defined' do
      allow(EdgeMetadataSyncWorker).to receive(:perform_async)
      step = build_step('cdn_sync')
      described_class.new(instance, step).call
      expect(EdgeMetadataSyncWorker).to have_received(:perform_async).with(asset.id)
    end
  end

  # ── Token rendering ──────────────────────────────────────────────────────

  describe 'token rendering' do
    it 'renders asset.title, asset.id, and workflow.name tokens' do
      step = build_step('in_app_notification', {
        'recipient' => 'uploader',
        'message'   => "Title:{{asset.title}} ID:{{asset.id}} Workflow:{{workflow.name}}",
      })
      described_class.new(instance, step).call
      note = Notification.last
      expect(note).to be_present
      expect(note.message).to include("Title:#{asset.title}")
      expect(note.message).to include("ID:#{asset.id}")
      expect(note.message).to include("Workflow:#{workflow.name}")
    end
  end
end

# ---- merged from workflow_action_executor_coverage_spec.rb ----
RSpec.describe WorkflowActionExecutor do
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:asset) { create(:asset, user: user, status: 'in_review', properties: { 'tags' => [ 'keep' ], 'rating' => '4.5', 'name' => 'hero-final.jpg' }) }
  let(:workflow) { create(:workflow, name: 'Review Flow') }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  def build_step(node_type, config = {})
    create(:workflow_step,
           workflow: workflow,
           step_type: 'automated_action',
           node_type: node_type,
           assignee_type: 'system',
           assignee_id: 0,
           step_config: config)
  end

  describe 'notification branches' do
    it 'sends email notifications to every admin with rendered body and priority defaults' do
      admin
      delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: true)

      without_partial_double_verification do
        allow(WorkflowMailer).to receive(:workflow_email).and_return(delivery)

        step = build(:workflow_step, workflow: workflow, node_type: 'email_notification', step_config: {
          'recipient' => 'admins',
          'subject' => '',
          'body' => 'Asset {{asset.title}} in {{workflow.name}}',
        })

        expect { described_class.new(instance, step).call }.to change(Notification, :count).by(1)
        expect(WorkflowMailer).to have_received(:workflow_email).with(hash_including(
          to: admin.email,
          subject: "Workflow update: #{asset.title}",
          body: "Asset #{asset.title} in Review Flow",
          priority: 'normal'
        ))
        expect(delivery).to have_received(:deliver_later)
      end
    end

    it 'returns nil for blank slack and teams channels without making HTTP calls' do
      allow(Faraday).to receive(:new)

      expect(described_class.new(instance, build_step('slack', { 'channel' => '' })).call).to be_nil
      expect(described_class.new(instance, build_step('teams', { 'channel' => nil })).call).to be_nil
      expect(Faraday).not_to have_received(:new)
    end

    it 'posts Teams cards with attention colors' do
      captured_body = nil
      conn = instance_double(Faraday::Connection)
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:run_request) do |_method, _url, body, _headers|
        captured_body = body
      end

      described_class.new(instance, build_step('teams', {
        'channel' => 'https://teams.example.com/hook',
        'message' => 'Look at {{asset.url}}',
        'color' => 'attention',
      })).call

      body = JSON.parse(captured_body)
      expect(body).to include('@type' => 'MessageCard', 'themeColor' => 'FF0000')
      expect(body['text']).to include(asset.id)
    end
  end

  describe 'integration branches' do
    let(:conn) { instance_double(Faraday::Connection, run_request: true) }

    before { allow(Faraday).to receive(:new).and_return(conn) }

    it 'merges JSON headers and basic auth for secure webhooks' do
      described_class.new(instance, build_step('secure_webhook', {
        'url' => 'https://hooks.example.com/basic',
        'headers' => '{"X-Trace":"abc"}',
        'authType' => 'basic',
        'secret' => 'encoded-creds',
      })).call

      expect(conn).to have_received(:run_request).with(
        :post,
        'https://hooks.example.com/basic',
        anything,
        hash_including('X-Trace' => 'abc', 'Authorization' => 'Basic encoded-creds', 'Content-Type' => 'application/json')
      )
    end

    it 'ignores malformed custom header JSON and skips blank webhook URLs' do
      blank_step = build(:workflow_step, workflow: workflow, node_type: 'webhook', step_config: { 'url' => '' })
      described_class.new(instance, blank_step).call
      expect(conn).not_to have_received(:run_request)

      described_class.new(instance, build_step('webhook', {
        'url' => 'https://hooks.example.com/malformed',
        'headers' => '{not json',
      })).call
      expect(conn).to have_received(:run_request).with(:post, 'https://hooks.example.com/malformed', anything, hash_including('Content-Type' => 'application/json'))
    end

    it 'logs and re-raises Faraday failures' do
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      allow(conn).to receive(:run_request).and_raise(Faraday::TimeoutError, 'slow')

      expect do
        described_class.new(instance, build_step('api_call', { 'url' => 'https://api.example.com', 'method' => 'PATCH' })).call
      end.to raise_error(Faraday::TimeoutError)
      expect(Rails.logger).to have_received(:warn).with(/HTTP PATCH https:\/\/api.example.com failed: slow/)
      expect(Rails.logger).to have_received(:error).with(/Step #.*api_call.*slow/)
    end
  end

  describe 'asset operation and flow branches' do
    it 'skips metadata updates when the legacy key is blank' do
      expect do
        described_class.new(instance, build_step('update_metadata', { 'metadataKey' => '', 'metadataValue' => 'ignored' })).call
      end.not_to change { asset.reload.properties }
    end

    it 'does not delete the original asset when resolving deletion targets' do
      stub_const('AssetCopyWorker', Class.new do
        def self.perform_async(*); end
      end)
      expect(AssetCopyWorker).to receive(:perform_async).with(asset.id, nil)
      described_class.new(instance, build_step('copy_asset', { 'folder' => '' })).call
    end

    it 'publishes and triggers CDN sync unless disabled' do
      allow(EdgeMetadataSyncWorker).to receive(:perform_async)

      described_class.new(instance, build_step('publish')).call

      expect(asset.reload.read_attribute_before_type_cast('status')).to eq(Asset.statuses['approved'].to_s)
      expect(EdgeMetadataSyncWorker).to have_received(:perform_async).with(asset.id)
    end

    it 'schedules delays in minutes and falls back to hours for unknown units' do
      allow(WorkflowDelayWorker).to receive(:perform_in)

      minute_step = build_step('delay', { 'delayValue' => 3, 'delayUnit' => 'minutes' })
      unknown_step = build_step('delay', { 'delayValue' => 2, 'delayUnit' => 'fortnights' })

      expect(described_class.new(instance, minute_step).call).to eq(:delay_scheduled)
      expect(described_class.new(instance, unknown_step).call).to eq(:delay_scheduled)
      expect(WorkflowDelayWorker).to have_received(:perform_in).with(180, instance.id, minute_step.id)
      expect(WorkflowDelayWorker).to have_received(:perform_in).with(7200, instance.id, unknown_step.id)
    end

    it 'evaluates all remaining condition operators and unknown fields' do
      expect(described_class.new(instance, build_step('condition', { 'field' => 'properties.name', 'operator' => 'contains', 'value' => 'final' })).call).to eq(:true_branch)
      expect(described_class.new(instance, build_step('condition', { 'field' => 'properties.name', 'operator' => 'ends_with', 'value' => '.jpg' })).call).to eq(:true_branch)
      expect(described_class.new(instance, build_step('condition', { 'field' => 'properties.rating', 'operator' => 'greater_than', 'value' => '4' })).call).to eq(:true_branch)
      expect(described_class.new(instance, build_step('condition', { 'field' => 'status', 'operator' => 'not_equals', 'value' => 'approved' })).call).to eq(:true_branch)
      expect(described_class.new(instance, build_step('condition', { 'field' => 'missing', 'operator' => 'bogus', 'value' => 'x' })).call).to eq(:false_branch)
      expect(described_class.new(instance, build_step('condition', { 'field' => '', 'operator' => 'equals', 'value' => '' })).call).to eq(:true_branch)
    end

    it 'logs and skips unknown node types' do
      allow(Rails.logger).to receive(:warn)

      unknown_step = build(:workflow_step, workflow: workflow, node_type: 'future_node')
      expect(described_class.new(instance, unknown_step).call).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/Unknown node_type 'future_node'/)
    end
  end
end

RSpec.describe WorkflowActionExecutor, 'additional branch coverage' do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user, status: 'in_review', properties: { 'tags' => [] }) }
  let(:workflow) { create(:workflow, name: 'Extra Flow') }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: 'in_progress') }

  def build_step(node_type, config = {})
    create(:workflow_step,
           workflow: workflow,
           step_type: 'automated_action',
           node_type: node_type,
           assignee_type: 'system',
           assignee_id: 0,
           logic: 'all',
           step_config: config)
  end

  it 'does not enqueue SMS when no SMS worker is defined' do
    hide_const('WorkflowSmsWorker')
    allow(Rails.logger).to receive(:info)

    described_class.new(instance, build_step('sms', { 'phone' => '+1', 'message' => 'Hello' })).call

    expect(Rails.logger).to have_received(:info).with(/SMS to \+1/)
  end

  it 'regenerates thumbnails through ImageProcessingWorker when available' do
    stub_const('ImageProcessingWorker', Class.new do
      def self.perform_async(*); end
    end)
    allow(ImageProcessingWorker).to receive(:perform_async)

    described_class.new(instance, build_step('generate_thumbnail')).call

    expect(ImageProcessingWorker).to have_received(:perform_async).with(asset.id)
  end

  it 'logs thumbnail regeneration when only the ingestion worker is available' do
    hide_const('ImageProcessingWorker')
    allow(Rails.logger).to receive(:info)

    described_class.new(instance, build_step('generate_thumbnail')).call

    expect(Rails.logger).to have_received(:info).with(/Thumbnail regen requested for Asset #{asset.id}/)
  end

  it 'skips AI metadata dispatch failures without re-raising' do
    allow(AiBatchJob).to receive(:create!).and_raise(ActiveRecord::ActiveRecordError, 'offline')
    allow(Rails.logger).to receive(:warn)

    expect(described_class.new(instance, build_step('ai_metadata')).call).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/AI metadata dispatch skipped: offline/)
  end

  it 'renders blank notification messages as empty strings' do
    expect do
      described_class.new(instance, build_step('in_app_notification', { 'recipient' => 'uploader', 'message' => nil })).call
    end.to change(Notification, :count).by(1)

    expect(Notification.last.message).to eq('')
  end
end
