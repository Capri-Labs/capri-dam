require "rails_helper"

RSpec.describe EmailTemplateDesignLibrary do
  describe "::DESIGNS" do
    it "provides exactly 10 predefined designs" do
      expect(described_class::DESIGNS.size).to eq(10)
    end

    it "gives every design a unique id" do
      ids = described_class::DESIGNS.map { |design| design[:id] }
      expect(ids.uniq.size).to eq(ids.size)
    end

    it "requires every design to have the fields the gallery/editor rely on" do
      described_class::DESIGNS.each do |design|
        expect(design[:id]).to be_present
        expect(design[:name]).to be_present
        expect(design[:category]).to be_in(EmailTemplate::CATEGORIES)
        expect(design[:description]).to be_present
        expect(design[:subject]).to be_present
        expect(design[:html_body]).to be_present
        expect(design[:text_body]).to be_present
      end
    end

    it "produces HTML that Liquid can parse without raising" do
      described_class::DESIGNS.each do |design|
        expect { Liquid::Template.parse(design[:html_body]) }.not_to raise_error
        expect { Liquid::Template.parse(design[:subject]) }.not_to raise_error
        expect { Liquid::Template.parse(design[:text_body]) }.not_to raise_error
      end
    end
  end
end
