require 'swagger_helper'

RSpec.describe 'Admin::UserGroups', type: :request do
  path '/admin/user_groups' do
    # 1. GET /admin/user_groups
    get 'Retrieves a list of all user groups with their hierarchy' do
      tags 'Admin - User Groups'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'user groups retrieved successfully' do
        schema type: :object,
               properties: {
                 user_groups: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :integer },
                       name: { type: :string },
                       description: { type: :string, nullable: true },
                       parent_id: { type: :integer, nullable: true },
                       member_count: { type: :integer }
                     }
                   }
                 }
               }

        run_test!
      end
    end

    # 2. POST /admin/user_groups
    post 'Creates a new user group' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          user_group: {
            type: :object,
            properties: {
              name: { type: :string, example: 'Marketing Team' },
              description: { type: :string, example: 'Global marketing and content creators' }
            },
            required: ['name']
          },
          parent_id: { type: :integer, nullable: true, description: 'Optional ID to nest this group under a parent' }
        },
        required: ['user_group']
      }

      response '201', 'user group created successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 group: { type: :object }
               }
        run_test!
      end

      response '422', 'unprocessable entity' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 errors: { type: :array, items: { type: :string } }
               }
        run_test!
      end
    end
  end

  path '/admin/user_groups/{id}/add_user' do
    parameter name: :id, in: :path, type: :string, description: 'User Group ID'

    # 3. POST /admin/user_groups/:id/add_user
    post 'Adds a user to the group via email' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          email: { type: :string, example: 'employee@example.com' }
        },
        required: ['email']
      }

      response '200', 'user added successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '404', 'user not found' do
        schema type: :object, properties: { success: { type: :boolean }, error: { type: :string } }
        run_test!
      end
    end
  end

  path '/admin/user_groups/{id}/remove_user' do
    parameter name: :id, in: :path, type: :string, description: 'User Group ID'

    # 4. DELETE /admin/user_groups/:id/remove_user
    delete 'Removes a user from the group via user ID' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      # Note: While DELETE requests typically use query params, passing a body is standard for nested resource destruction APIs
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          user_id: { type: :integer, example: 42 }
        },
        required: ['user_id']
      }

      response '200', 'user removed successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end
end