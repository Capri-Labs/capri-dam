# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CommentNotificationService do
  let(:thread_author) { create(:user, email: 'thread@example.com') }
  let(:participant) { create(:user, email: 'participant@example.com') }
  let(:mentioned_user) { create(:user, username: 'mentioned', email: 'mentioned@example.com') }
  let(:comment_author) { create(:user, email: 'author@example.com') }
  let(:asset) { create(:asset, user: thread_author, title: 'Campaign Hero') }
  let(:version) { create(:asset_version, asset: asset, version_number: 1) }
  let(:thread) { asset.comment_threads.create!(created_by: thread_author, origin_version: version) }

  before do
    thread.comments.create!(body: 'Original feedback', author: participant, asset_version: version)
    thread.comments.create!(body: 'Mention participant', author: mentioned_user, asset_version: version)
    allow(MentionProcessorWorker).to receive(:perform_async)
    allow(EmailOrchestrator).to receive(:trigger)
  end

  describe '#deliver' do
    it 'enqueues mention processing with the comment as the polymorphic reference' do
      comment = thread.comments.create!(body: 'Please ask @mentioned', author: comment_author, asset_version: version)

      described_class.new(comment).deliver

      expect(MentionProcessorWorker).to have_received(:perform_async).with(
        'Please ask @mentioned',
        comment_author.id,
        a_string_ending_with("/assets?id=#{asset.uuid}&thread=#{thread.id}"),
        'Comment',
        comment.id
      )
    end

    it "creates notifications for participants but not the comment's author" do
      comment = thread.comments.create!(body: 'New reply', author: comment_author, asset_version: version)

      expect { described_class.new(comment).deliver }.to change(Notification, :count).by(3)
      expect(Notification.where(user: thread_author)).to exist
      expect(Notification.where(user: participant)).to exist
      expect(Notification.where(user: mentioned_user)).to exist
      expect(Notification.where(user: comment_author)).not_to exist
    end

    it 'does not double-notify users who were mentioned' do
      comment = thread.comments.create!(body: 'Looping in @mentioned', author: comment_author, asset_version: version)

      described_class.new(comment).deliver

      expect(Notification.where(user: mentioned_user)).not_to exist
      expect(Notification.where(user: thread_author)).to exist
      expect(Notification.where(user: participant)).to exist
    end

    it 'triggers comment_created email for each non-mentioned participant recipient' do
      comment = thread.comments.create!(body: 'Looping in @mentioned', author: comment_author, asset_version: version)

      described_class.new(comment).deliver

      expect(EmailOrchestrator).to have_received(:trigger).with(
        'comment_created',
        thread_author.email,
        hash_including('comment' => hash_including('body' => 'Looping in @mentioned'))
      )
      expect(EmailOrchestrator).to have_received(:trigger).with(
        'comment_created',
        participant.email,
        hash_including('asset' => hash_including('name' => 'Campaign Hero'))
      )
      expect(EmailOrchestrator).not_to have_received(:trigger).with(
        'comment_created',
        mentioned_user.email,
        anything
      )
    end
  end

  describe '#deliver_resolution' do
    it 'notifies the thread author and triggers comment_resolved email' do
      resolver = create(:user)
      comment = thread.comments.create!(body: 'Closing this', author: comment_author, asset_version: version)
      thread.resolve!(user: resolver, status: 'verified')

      expect {
        described_class.new(comment).deliver_resolution(by: resolver)
      }.to change(Notification.where(user: thread_author), :count).by(1)

      expect(EmailOrchestrator).to have_received(:trigger).with(
        'comment_resolved',
        thread_author.email,
        hash_including('comment' => hash_including('status' => 'verified'))
      )
    end

    it 'does not notify the resolver when they authored the thread' do
      comment = thread.comments.create!(body: 'Closing own thread', author: comment_author, asset_version: version)
      thread.resolve!(user: thread_author, status: 'resolved')

      expect {
        described_class.new(comment).deliver_resolution(by: thread_author)
      }.not_to change(Notification, :count)
      expect(EmailOrchestrator).not_to have_received(:trigger).with('comment_resolved', thread_author.email, anything)
    end
  end
end
