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
