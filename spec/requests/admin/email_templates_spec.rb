require 'swagger_helper'

RSpec.describe 'Admin::EmailTemplates', type: :request do
  path '/admin/email_templates' do
    # 1. GET /admin/email_templates
    get 'Retrieves a list of all email templates' do
      tags 'Admin - Email Templates'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'email templates retrieved successfully' do
        schema type: :object,
               properties: {
                 email_templates: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :integer },
                       name: { type: :string },
                       event_trigger: { type: :string },
                       subject: { type: :string },
                       active: { type: :boolean },
                       updated_at: { type: :string }
                     }
                   }
                 }
               }
        run_test!
      end
    end

    # 2. POST /admin/email_templates
    post 'Creates a new email template' do
      tags 'Admin - Email Templates'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          email_template: {
            type: :object,
            properties: {
              name: { type: :string, example: 'Welcome Email' },
              event_trigger: { type: :string, example: 'user_created' },
              subject: { type: :string, example: 'Welcome to Headless DAM' },
              html_body: { type: :string, example: '<h1>Welcome {{first_name}}</h1>' },
              text_body: { type: :string, example: 'Welcome {{first_name}}' },
              active: { type: :boolean, example: true }
            },
            required: ['name', 'event_trigger', 'subject']
          }
        },
        required: ['email_template']
      }

      response '200', 'template created successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '200', 'validation failed' do
        # Note: Controller renders 200 OK with success: false on validation failure
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path '/admin/email_templates/{id}' do
    parameter name: :id, in: :path, type: :string, description: 'Email Template ID'

    # 3. GET /admin/email_templates/:id
    get 'Retrieves details of a specific email template' do
      tags 'Admin - Email Templates'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'template details retrieved' do
        schema type: :object,
               properties: {
                 email_template: {
                   type: :object,
                   properties: {
                     id: { type: :integer },
                     name: { type: :string },
                     event_trigger: { type: :string },
                     subject: { type: :string },
                     html_body: { type: :string },
                     text_body: { type: :string },
                     active: { type: :boolean },
                     created_at: { type: :string, format: 'date-time' },
                     updated_at: { type: :string, format: 'date-time' }
                   }
                 }
               }
        run_test!
      end
    end

    # 4. PATCH /admin/email_templates/:id
    patch 'Updates an existing email template' do
      tags 'Admin - Email Templates'
      consumes 'application/json'
      produces 'application/json'
      security [Bearer: []]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          email_template: {
            type: :object,
            properties: {
              name: { type: :string },
              event_trigger: { type: :string },
              subject: { type: :string },
              html_body: { type: :string },
              text_body: { type: :string },
              active: { type: :boolean }
            }
          }
        }
      }

      response '200', 'template updated successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '200', 'update failed' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end

    # 5. DELETE /admin/email_templates/:id
    delete 'Deletes an email template' do
      tags 'Admin - Email Templates'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'template deleted successfully' do
        schema type: :object, properties: { success: { type: :boolean }, message: { type: :string } }
        run_test!
      end

      response '200', 'deletion failed' do
        schema type: :object, properties: { success: { type: :boolean }, errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end
end