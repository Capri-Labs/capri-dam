require 'swagger_helper'

# == User Groups API
#
# Manages hierarchical groups of DAM users.
# Built-in system groups (everyone, administrators, super-administrators)
# are protected: they cannot be deleted and have restricted mutation rules.
RSpec.describe 'Admin::UserGroups', type: :request do
  # ---------------------------------------------------------------------------
  # Collection
  # ---------------------------------------------------------------------------

  path '/admin/user_groups' do
    get 'Retrieves all user groups with hierarchy metadata' do
      tags 'Admin - User Groups'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'user groups retrieved successfully' do
        schema type: :object,
               properties: {
                 user_groups: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:           { type: :integer },
                       name:         { type: :string },
                       slug:         { type: :string, nullable: true },
                       description:  { type: :string, nullable: true },
                       is_system:    { type: :boolean },
                       parent_id:    { type: :integer, nullable: true },
                       member_count: { type: :integer },
                     },
                   },
                 },
               }
        run_test!
      end
    end

    post 'Creates a new user group' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'user_group' ],
        properties: {
          user_group: {
            type: :object,
            required: [ 'name' ],
            properties: {
              name:        { type: :string, example: 'Marketing Team' },
              description: { type: :string, example: 'Global marketing and content creators' },
            },
          },
          parent_id: { type: :integer, nullable: true,
                       description: 'Optional — nests this group under a parent' },
        },
      }

      response '201', 'user group created' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 group:   { '$ref' => '#/components/schemas/UserGroup' },
               }
        run_test!
      end

      response '422', 'validation failed' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 errors:  { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Single group
  # ---------------------------------------------------------------------------

  path '/admin/user_groups/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'User Group ID'

    get 'Retrieves a single group with members and sub-groups' do
      tags 'Admin - User Groups'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'group retrieved' do
        schema type: :object,
               properties: {
                 group: { '$ref' => '#/components/schemas/UserGroup' },
               }
        run_test!
      end

      response '404', 'group not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    patch 'Updates a group name or description' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          user_group: {
            type: :object,
            properties: {
              name:        { type: :string },
              description: { type: :string },
            },
          },
        },
      }

      response '200', 'group updated' do
        schema type: :object, properties: { success: { type: :boolean }, group: { type: :object } }
        run_test!
      end

      response '403', 'forbidden — only super-admins can modify administrators group' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    delete 'Deletes a non-system group' do
      tags 'Admin - User Groups'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'group deleted' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '403', 'system groups cannot be deleted' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Member management (users)
  # ---------------------------------------------------------------------------

  path '/admin/user_groups/{id}/add_member' do
    parameter name: :id, in: :path, type: :string, description: 'User Group ID'

    post 'Adds a user member to the group' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          email:   { type: :string,  example: 'employee@example.com',
                     description: 'Look up by email (preferred)' },
          user_id: { type: :integer, example: 42,
                     description: 'Alternatively look up by ID' },
        },
      }

      response '200', 'user added to group' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '403', 'cannot add users to everyone or administrators without super-admin' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'user not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/admin/user_groups/{id}/remove_member' do
    parameter name: :id, in: :path, type: :string, description: 'User Group ID'

    delete 'Removes a user from the group' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'user_id' ],
        properties: {
          user_id: { type: :integer, example: 42 },
        },
      }

      response '200', 'user removed' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '403', 'cannot remove users from everyone group' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Sub-group (group-in-group) management
  # ---------------------------------------------------------------------------

  path '/admin/user_groups/{id}/add_group_member' do
    parameter name: :id, in: :path, type: :string, description: 'Parent Group ID'

    post 'Nests a child group inside this group' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'child_group_id' ],
        properties: {
          child_group_id: { type: :integer, description: 'ID of the group to nest' },
        },
      }

      response '200', 'sub-group added' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '404', 'parent or child group not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'validation failed (e.g. circular nesting)' do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 errors:  { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  path '/admin/user_groups/{id}/remove_group_member' do
    parameter name: :id, in: :path, type: :string, description: 'Parent Group ID'

    delete 'Removes a child group from this group' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'child_group_id' ],
        properties: {
          child_group_id: { type: :integer },
        },
      }

      response '200', 'sub-group removed' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Legacy aliases (backward-compat)
  # ---------------------------------------------------------------------------

  path '/admin/user_groups/{id}/add_user' do
    parameter name: :id, in: :path, type: :string, description: 'User Group ID'

    post '(Deprecated) Adds a user via email — use add_member instead' do
      tags 'Admin - User Groups'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ 'email' ],
        properties: { email: { type: :string } },
      }

      response '200', 'user added' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end
    end
  end
end
