require "rails_helper"

RSpec.describe EmailDispatcherWorker, type: :worker do
  let(:template) { create(:email_template, subject: "Hello {{name}}", html_body: "<p>{{name}}</p>", text_body: "{{name}}") }
  let(:delivery) { create(:email_delivery, email_template: template, payload: { "name" => "Ada" }) }

  it "returns early when delivery is missing or already sent" do
    sent = create(:email_delivery, status: "sent")

    expect { described_class.new.perform(0) }.not_to raise_error
    expect(DynamicMailer).not_to receive(:dispatch_email)
    described_class.new.perform(sent.id)
  end

  it "renders Liquid templates, sends mail and marks delivery sent" do
    message = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(DynamicMailer).to receive(:dispatch_email).and_return(message)

    described_class.new.perform(delivery.id)

    expect(DynamicMailer).to have_received(:dispatch_email).with(
      to: delivery.recipient_email,
      subject: "Hello Ada",
      html_body: "<p>Ada</p>",
      text_body: "Ada"
    )
    expect(delivery.reload.status).to eq("sent")
  end

  it "increments retry count, records the error and reraises delivery failures" do
    message = instance_double(ActionMailer::MessageDelivery)
    allow(DynamicMailer).to receive(:dispatch_email).and_return(message)
    allow(message).to receive(:deliver_now).and_raise(StandardError, "smtp down")

    expect { described_class.new.perform(delivery.id) }.to raise_error(StandardError, "smtp down")
    expect(delivery.reload.retry_count).to eq(1)
    expect(delivery.error_log).to include("smtp down")
  end

  it "marks the delivery failed when Sidekiq retries are exhausted and ignores missing deliveries" do
    described_class.sidekiq_retries_exhausted_block.call(
      { "args" => [ delivery.id ] },
      StandardError.new("smtp permanently down")
    )

    expect(delivery.reload.status).to eq("failed")
    expect(delivery.error_log).to include("Final SMTP Error: smtp permanently down")

    expect do
      described_class.sidekiq_retries_exhausted_block.call(
        { "args" => [ 0 ] },
        StandardError.new("missing")
      )
    end.not_to raise_error
  end
end
