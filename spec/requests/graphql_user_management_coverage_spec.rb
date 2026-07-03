require "rails_helper"

RSpec.describe "GraphQL user management coverage", type: :request do
  def schema_exec(query, variables: {}, context: {})
    HeadlessDamSchema.execute(query, variables: variables, context: context).to_h
  end

  it "rejects unauthenticated createUser and deleteUserGroup mutations" do
    create_user = <<~GQL
      mutation($input: CreateUserInput!) {
        createUser(input: $input) { user { id } errors }
      }
    GQL
    delete_group = <<~GQL
      mutation($input: DeleteUserGroupInput!) {
        deleteUserGroup(input: $input) { success errors }
      }
    GQL

    create_body = schema_exec(create_user, variables: { input: { email: "anon@example.com", firstName: "Anon", lastName: "User" } })
    delete_body = schema_exec(delete_group, variables: { input: { id: 0 } })

    expect(create_body.dig("data", "createUser", "errors")).to include("Unauthorized")
    expect(delete_body.dig("data", "deleteUserGroup", "errors")).to include("Unauthorized")
  end
end
