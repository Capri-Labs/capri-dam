require "rails_helper"

RSpec.describe "GraphQL customNodeDefinitions", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:viewer) { create(:user) }

  def gql_post(query:, user:)
    sign_in(user)
    post "/graphql", params: { query: query }.to_json,
                     headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    JSON.parse(response.body)
  end

  it "returns safe manifests for admins" do
    definition = create(:custom_node_definition)
    query = "{ customNodeDefinitions { id key nodeType runtime status circuitOpen } }"

    body = gql_post(query: query, user: admin)

    item = body.dig("data", "customNodeDefinitions").first
    expect(item["key"]).to eq(definition.key)
    expect(item["nodeType"]).to eq(definition.node_type)
    expect(item["runtime"]).not_to have_key("secret")
  end

  it "returns an empty list for non-admin users" do
    create(:custom_node_definition)

    body = gql_post(query: "{ customNodeDefinitions { id } }", user: viewer)

    expect(body.dig("data", "customNodeDefinitions")).to eq([])
  end
end
