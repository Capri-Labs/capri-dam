require "rails_helper"

RSpec.describe Admin::IntelligenceController, type: :controller do
  include Devise::Test::ControllerHelpers

  before do
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw { get "copilot" => "admin/intelligence#copilot" }
  end

  it "assigns the active view before Rails reports the missing unrouted template" do
    expect { get :copilot }.to raise_error(ActionController::MissingExactTemplate)
    expect(assigns(:active_view)).to eq("Semantic Copilot")
  end
end
