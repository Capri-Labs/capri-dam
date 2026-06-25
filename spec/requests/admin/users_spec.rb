require 'swagger_helper'

RSpec.describe 'Admin::Users', type: :request do
  path '/admin/users' do
    # 1. GET /admin/users
    get 'Retrieves a list of all users' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

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
                       group_ids: { type: :array, items: { type: :integer } },
                     },
                   },
                 },
               }

        run_test!
      end
    end

    # 2. POST /admin/users
    post 'Creates a new user' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

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
              role: { type: :string, example: 'viewer' },
              admin: { type: :boolean, example: false },
              user_group_ids: { type: :array, items: { type: :integer }, example: [ 1, 2 ] },
            },
            required: [ 'email', 'first_name', 'last_name' ],
          },
        },
      }

      response '200', 'user created successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
                 user:    { '$ref' => '#/components/schemas/User' },
               }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    get 'Retrieves a single user (with impersonators and preferences)' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'user retrieved' do
        schema type: :object, properties: { user: { '$ref' => '#/components/schemas/User' } }
        run_test!
      end

      response '404', 'user not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    # 3. PATCH /admin/users/:id
    patch 'Updates an existing user' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

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
              user_group_ids: { type: :array, items: { type: :integer } },
            },
          },
        },
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

    delete 'Deactivates a user (soft delete)' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'user deactivated' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/toggle_status' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    post 'Toggles a user between active and suspended states' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'status toggled successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
                 active:  { type: :boolean },
               }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/change_password' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    post 'Changes a local user password (admin initiated)' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'new_password', 'new_password_confirmation' ],
        properties: {
          new_password:              { type: :string, example: 'NewSecure#123' },
          new_password_confirmation: { type: :string, example: 'NewSecure#123' },
          force_change: { type: :boolean, example: false,
                          description: 'When true the user must change on next login' },
        },
      }

      response '200', 'password updated' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '422', 'SSO accounts cannot have password changed here' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/groups' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    get 'Lists the groups this user belongs to' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'groups retrieved' do
        schema type: :object,
               properties: {
                 groups: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:        { type: :integer },
                       name:      { type: :string },
                       slug:      { type: :string, nullable: true },
                       is_system: { type: :boolean },
                     },
                   },
                 },
               }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/impersonators' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    get 'Lists users allowed to impersonate this account' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'impersonators retrieved' do
        schema type: :object,
               properties: {
                 impersonators: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:           { type: :integer },
                       display_name: { type: :string },
                       email:        { type: :string },
                     },
                   },
                 },
               }
        run_test!
      end
    end

    post 'Grants impersonation access to another user' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'impersonator_id' ],
        properties: {
          impersonator_id: { type: :integer, description: 'ID of the user to grant impersonation to' },
        },
      }

      response '200', 'impersonation access granted' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '422', 'self-impersonation or duplicate grant' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/impersonators/{impersonator_id}' do
    parameter name: :id,             in: :path, type: :string, description: 'User ID'
    parameter name: :impersonator_id, in: :path, type: :string, description: 'Impersonator User ID'

    delete 'Revokes impersonation access' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'impersonation access revoked' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end

  path '/admin/users/{id}/preferences' do
    parameter name: :id, in: :path, type: :string, description: 'User ID'

    get 'Retrieves user preferences (language, notifications)' do
      tags 'Admin - Users'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'preferences retrieved' do
        schema type: :object,
               properties: {
                 preferences: {
                   type: :object,
                   properties: {
                     language:                { type: :string, example: 'en' },
                     receive_mention_emails:  { type: :boolean },
                     receive_workflow_emails: { type: :boolean },
                   },
                 },
               }
        run_test!
      end
    end

    patch 'Updates user preferences' do
      tags 'Admin - Users'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          preferences: {
            type: :object,
            properties: {
              language:                { type: :string, example: 'de' },
              receive_mention_emails:  { type: :boolean },
              receive_workflow_emails: { type: :boolean },
            },
          },
        },
      }

      response '200', 'preferences updated' do
        schema type: :object,
               properties: {
                 success:     { type: :boolean },
                 preferences: { type: :object },
               }
        run_test!
      end
    end
  end
end
