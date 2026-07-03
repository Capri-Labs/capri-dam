require "rails_helper"

RSpec.describe Types::InboxMessageType do
  describe "#snippet" do
    subject(:snippet) { type_instance.snippet }

    let(:type_instance) do
      described_class.allocate.tap do |instance|
        allow(instance).to receive(:object).and_return(message)
      end
    end

    context "when body_text is blank" do
      let(:message) { instance_double(InboxMessage, body_text: "") }

      it { is_expected.to be_nil }
    end

    context "when body_text is present" do
      let(:message) { instance_double(InboxMessage, body_text: "a" * 200) }

      it "returns a truncated preview" do
        expect(snippet).to eq("#{"a" * 147}...")
      end
    end
  end
end
