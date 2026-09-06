# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Comment, type: :model do
  let(:author) { create(:user, email: 'author@example.com') }
  let(:asset) { create(:asset, user: author) }
  let(:version) { create(:asset_version, asset: asset, version_number: 1) }
  let(:thread) { CommentThread.create!(asset: asset, origin_version: version, created_by: author) }

  def build_comment(**attributes)
    described_class.new({ comment_thread: thread, body: 'Looks good', author: author, asset_version: version }.merge(attributes))
  end

  describe 'associations' do
    it 'belongs to a thread and can have replies and annotations' do
      comment = build_comment.tap(&:save!)
      reply = thread.comments.create!(body: 'Reply', author: author, asset_version: version, parent_comment: comment)
      annotation = comment.annotation_targets.create!(shape: 'rect', bbox_x: 0.1, bbox_y: 0.1, bbox_w: 0.2, bbox_h: 0.2)

      expect(comment.replies).to include(reply)
      expect(comment.annotation_targets).to include(annotation)
      expect(comment.asset).to eq(asset)
    end
  end

  describe 'validations' do
    it 'validates motivation inclusion' do
      expect(build_comment(motivation: 'invalid')).not_to be_valid
    end

    it 'validates agent type inclusion' do
      expect(build_comment(agent_type: 'bot')).not_to be_valid
    end

    it 'requires an author for person comments' do
      comment = build_comment(author: nil, agent_type: 'person')

      expect(comment).not_to be_valid
      expect(comment.errors[:author]).to include('must be present for a person-authored comment')
    end

    it 'allows software comments without a human author' do
      comment = build_comment(author: nil, agent_type: 'software', agent_name: 'Review Bot')

      expect(comment).to be_valid
    end

    it 'rejects replies to replies' do
      parent = build_comment.tap(&:save!)
      reply = thread.comments.create!(body: 'Reply', author: author, asset_version: version, parent_comment: parent)
      nested = build_comment(parent_comment: reply)

      expect(nested).not_to be_valid
      expect(nested.errors[:parent_comment]).to include('cannot be a reply — threading is single-level')
    end

    it 'rejects replies whose parent belongs to another thread' do
      other_thread = CommentThread.create!(asset: asset, origin_version: version, created_by: author)
      other_comment = other_thread.comments.create!(body: 'Elsewhere', author: author, asset_version: version)

      comment = build_comment(parent_comment: other_comment)

      expect(comment).not_to be_valid
      expect(comment.errors[:parent_comment]).to include('must belong to the same thread')
    end
  end

  describe '#author_display_name' do
    it 'uses the human author email for person comments' do
      expect(build_comment.author_display_name).to eq('author@example.com')
    end

    it 'uses the agent name for software comments' do
      comment = build_comment(author: nil, agent_type: 'software', agent_name: 'Review Bot')

      expect(comment.author_display_name).to eq('Review Bot')
    end

    it 'falls back for unnamed software agents' do
      comment = build_comment(author: nil, agent_type: 'software', agent_name: nil)

      expect(comment.author_display_name).to eq('Assistant')
    end
  end

  describe '#edit!' do
    it 'updates the body and stamps edited_at' do
      comment = build_comment.tap(&:save!)

      comment.edit!('Updated body')

      expect(comment.body).to eq('Updated body')
      expect(comment.edited_at).to be_present
      expect(comment).to be_edited
    end
  end
end
