require 'rails_helper'

RSpec.describe WorkflowActionExecutor do
  let(:user)     { create(:user) }
  let(:asset)    { create(:asset, user: user, status: 'in_review') }
  let(:workflow) { create(:workflow) }
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

  describe 'asset operations' do
    it 'set_status updates the asset status' do
      step = build_step('set_status', { 'status' => 'approved' })
      described_class.new(instance, step).call
      # assets.status is a string column backed by an integer enum, so compare
      # against the stored representation the rest of the app writes.
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

    it 'update_metadata writes a property with token substitution' do
      step = build_step('update_metadata', { 'metadataKey' => 'campaign', 'metadataValue' => 'Asset {{asset.id}}' })
      described_class.new(instance, step).call
      expect(asset.reload.properties['campaign']).to eq("Asset #{asset.id}")
    end
  end

  describe 'notifications' do
    it 'in_app_notification creates a Notification for the uploader' do
      step = build_step('in_app_notification', { 'recipient' => 'uploader', 'message' => 'Review {{asset.title}}' })
      expect { described_class.new(instance, step).call }.to change(Notification, :count).by(1)
      note = Notification.last
      expect(note.user).to eq(user)
      expect(note.message).to include(asset.title)
    end
  end

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
  end

  describe 'integrations' do
    it 'webhook posts a JSON payload via Faraday' do
      conn = instance_double(Faraday::Connection)
      allow(Faraday).to receive(:new).and_return(conn)
      expect(conn).to receive(:run_request)
        .with(:post, 'https://hooks.example.com/dam', anything, hash_including('Content-Type' => 'application/json'))

      step = build_step('webhook', { 'url' => 'https://hooks.example.com/dam', 'method' => 'POST' })
      described_class.new(instance, step).call
    end

    it 'secure_webhook adds an HMAC signature header' do
      conn = instance_double(Faraday::Connection)
      allow(Faraday).to receive(:new).and_return(conn)
      expect(conn).to receive(:run_request)
        .with(:post, 'https://hooks.example.com/secure', anything, hash_including('X-Signature-SHA256' => /\A[0-9a-f]{64}\z/))

      step = build_step('secure_webhook', { 'url' => 'https://hooks.example.com/secure', 'authType' => 'hmac', 'secret' => 's3cr3t' })
      described_class.new(instance, step).call
    end
  end
end
