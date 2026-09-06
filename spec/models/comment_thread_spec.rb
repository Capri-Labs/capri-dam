# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommentThread, type: :model do
  let(:author) { create(:user) }
  let(:asset) { create(:asset, user: author) }
  let(:version_one) { create(:asset_version, asset: asset, version_number: 1) }
  let(:version_two) { create(:asset_version, asset: asset, version_number: 2) }

  def create_thread(**attributes)
    described_class.create!({ asset: asset, origin_version: version_one, created_by: author }.merge(attributes))
  end

  describe 'associations' do
    it 'belongs to an asset, origin version and creator' do
      thread = create_thread

      expect(thread.asset).to eq(asset)
      expect(thread.origin_version).to eq(version_one)
      expect(thread.created_by).to eq(author)
    end

    it 'has comments and annotation targets' do
      thread = create_thread
      comment = thread.comments.create!(body: 'Annotated', author: author, asset_version: version_one)
      annotation = comment.annotation_targets.create!(shape: 'rect', bbox_x: 0.1, bbox_y: 0.1, bbox_w: 0.2, bbox_h: 0.2)

      expect(thread.comments).to include(comment)
      expect(thread.annotation_targets).to include(annotation)
    end
  end

  describe 'validations' do
    it 'validates status inclusion' do
      thread = create_thread
      thread.status = 'archived'

      expect(thread).not_to be_valid
      expect(thread.errors[:status]).to be_present
    end
  end

  describe 'visibility validation' do
    it 'rejects unsupported values' do
      thread = create_thread
      thread.visibility = 'public'

      expect(thread).not_to be_valid
      expect(thread.errors[:visibility]).to be_present
    end
  end

  describe '#resolve! and #reopen!' do
    it 'records resolution attribution and closes the thread' do
      resolver = create(:user)
      thread = create_thread

      thread.resolve!(user: resolver, status: 'verified')

      expect(thread).to be_closed
      expect(thread.status).to eq('verified')
      expect(thread.resolved_at).to be_present
      expect(thread.resolved_by).to eq(resolver)
    end

    it 'rejects unsupported resolve statuses' do
      expect { create_thread.resolve!(user: author, status: 'addressed') }.to raise_error(ArgumentError)
    end

    it 'reopens a closed thread and clears resolution' do
      thread = create_thread(status: 'resolved', resolved_at: Time.current, resolved_by: author)

      thread.reopen!

      expect(thread.status).to eq('open')
      expect(thread.resolved_at).to be_nil
      expect(thread.resolved_by).to be_nil
      expect(thread).not_to be_closed
    end
  end

  describe '#participants' do
    it 'returns unique active human commenters' do
      participant = create(:user)
      deleted_participant = create(:user)
      thread = create_thread
      thread.comments.create!(body: 'One', author: author, asset_version: version_one)
      thread.comments.create!(body: 'Two', author: participant, asset_version: version_one)
      thread.comments.create!(body: 'Deleted', author: deleted_participant, asset_version: version_one, deleted_at: Time.current)

      expect(thread.participants).to contain_exactly(author, participant)
    end
  end

  describe '#latest_commented_version' do
    it 'returns the highest version number among active comments' do
      thread = create_thread
      thread.comments.create!(body: 'Old', author: author, asset_version: version_one)
      thread.comments.create!(body: 'New', author: author, asset_version: version_two)

      expect(thread.latest_commented_version).to eq(version_two)
    end
  end
end
