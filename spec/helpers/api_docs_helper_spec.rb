require 'rails_helper'

# Specs in this file have access to a helper object that includes
# the ApiDocsHelper. For example:
#
# describe ApiDocsHelper do
#   describe "string concat" do
#     it "concats two strings with spaces" do
#       expect(helper.concat_strings("this","that")).to eq("this that")
#     end
#   end
# end
RSpec.describe ApiDocsHelper, type: :helper do
  it 'is an empty module with no public methods' do
    expect(ApiDocsHelper.instance_methods(false)).to be_empty
  end
end
