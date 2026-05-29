require 'swagger_helper'

RSpec.describe 'Admin::Users', type: :request do
  path '/admin/users' do
    # 1. GET /admin/users
    get 'Retrieves a list of all users' do
      tags 'Admin - Users'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'users retrieved successfully' do
        schema type: :object,
               properties: {
                 users: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :integer },
                       email: { type: :string },
                       display_name: { type: :string, nullable: true },
                       first_name: { type: :string },
                       last_name: { type: :string },
                       department: { type: :string, nullable: true },
                       role: { type: :string, nullable: true },
                       avatar_url: { type: :string, nullable: true },
                       sso_managed: { type: :boolean },
                       admin: { type: :boolean },
                       provider: { type: :string, nullable: true },
                       active: { type: :boolean },
                       created_at: { type: :string },
                       groups: { type: :array, items: { type: :string } },
                       group_ids: { type: :array, items: { type: :integer } }
                     }
                   }
                 }
               }

        run_test!
      end
    end

    # 2. POST /admin/users
    post 'Creates a new user' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            properties: {
              email: { type: :string, example: 'new_hire@example.com' },
              first_name: { type: :string, example: 'Jane' },
              last_name: { type: :string, example: 'Doe' },
              department: { type: :string, example: 'Marketing' },
              role: { type: :string, example: 'Content Creator' },
              admin: { type: :boolean, example: false },
              user_group_ids: { type: :array, items: { type: :integer }, example: [1, 2] }
            },
            required: ['email', 'first_name', 'last_name']
          }
        }
      }

      response '200', 'user created successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '200', 'validation failed' do
        # Note: The controller currently renders 200 OK even on failure, returning { success: false }
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    # 3. PATCH /admin/users/:id
    patch 'Updates an existing user' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            properties: {
              email: { type: :string },
              first_name: { type: :string },
              last_name: { type: :string },
              department: { type: :string },
              role: { type: :string },
              admin: { type: :boolean },
              user_group_ids: { type: :array, items: { type: :integer } }
            }
          }
        }
      }

      response '200', 'user updated successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '403', 'forbidden (unauthorized admin modification)' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/toggle_status' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    # 4. POST /admin/users/:id/toggle_status
    post 'Toggles a user between active and suspended states' do
      tags 'Admin - Users'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'status toggled successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
                 active: { type: :boolean }
               }
        run_test!
      end
    end
  end
end