require "rails_helper"

RSpec.describe PublishSchedulerWorker, type: :worker do
  let(:user) { create(:user) }

  it "applies due publish schedules and marks them completed" do
    asset = create(:asset)
    due = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: "publish",
                                             scheduled_at: 1.minute.ago)

    described_class.new.perform

    expect(asset.reload).to be_published
    expect(due.reload).to be_completed
  end

  it "applies due unpublish schedules" do
    asset = create(:asset)
    asset.publish!
    due = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: "unpublish",
                                             scheduled_at: 1.minute.ago)

    described_class.new.perform

    expect(asset.reload).not_to be_published
    expect(due.reload).to be_completed
  end

  it "does not touch schedules that are not yet due" do
    asset = create(:asset)
    future = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: "publish",
                                                scheduled_at: 1.hour.from_now)

    described_class.new.perform

    expect(asset.reload).not_to be_published
    expect(future.reload).to be_pending
  end

  it "logs and continues when one schedule fails to apply" do
    asset = create(:asset)
    due = create(:scheduled_publish_action, asset: asset, created_by: user, action_type: "publish",
                                             scheduled_at: 1.minute.ago)
    other_asset = create(:asset)
    other_due = create(:scheduled_publish_action, asset: other_asset, created_by: user, action_type: "publish",
                                                   scheduled_at: 1.minute.ago)

    allow_any_instance_of(Asset).to receive(:publish!).and_wrap_original do |method, *args|
      method.receiver == asset ? raise(StandardError, "boom") : method.call(*args)
    end

    expect { described_class.new.perform }.not_to raise_error

    expect(due.reload).to be_failed
    expect(other_due.reload).to be_completed
  end
end
