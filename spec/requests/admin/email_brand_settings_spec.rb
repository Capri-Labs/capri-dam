require 'swagger_helper'

# == Email Brand Settings API (Communication Engine tab)
#
# Powers the "Communication Engine" tab on the Email Engine admin screen:
# a single, org-wide custom CSS block (plus a couple of brand tokens) that is
# injected into every outbound system email by EmailDispatcherWorker,
# regardless of which EmailTemplate is being sent. This is intentionally
# decoupled from any individual template record.
RSpec.describe 'Admin::EmailBrandSettings', type: :request do
  path '/admin/email_templates/brand_settings' do
    get 'Retrieves the current global email brand CSS configuration' do
      tags 'Admin - Email Templates'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'brand settings retrieved successfully' do
        let(:admin) { create(:user, :admin) }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 brand_settings: {
                   type: :object,
                   properties: {
                     custom_css: { type: :string },
                     primary_color: { type: :string },
                     font_family: { type: :string },
                     preview_style_block: { type: :string },
                   },
                 },
               }
        run_test!
      end

      response '403', 'forbidden for non-admin users' do
        let(:user) { create(:user) }

        before { sign_in user }

        schema type: :object,
               properties: {
                 error: { type: :string },
               }
        run_test!
      end
    end

    patch 'Updates the global email brand CSS configuration' do
      tags 'Admin - Email Templates'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :brand_settings, in: :body, schema: {
        type: :object,
        properties: {
          brand_settings: {
            type: :object,
            properties: {
              custom_css: { type: :string },
              primary_color: { type: :string },
              font_family: { type: :string },
            },
          },
        },
      }

      response '200', 'brand settings saved successfully' do
        let(:admin) { create(:user, :admin) }
        let(:brand_settings) { { brand_settings: { custom_css: 'body { color: #1a56db; }', primary_color: '#1a56db', font_family: 'Georgia, serif' } } }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
                 brand_settings: {
                   type: :object,
                   properties: {
                     custom_css: { type: :string },
                     primary_color: { type: :string },
                     font_family: { type: :string },
                     preview_style_block: { type: :string },
                   },
                 },
               }
        run_test!
      end

      response '200', 'validation errors are returned for invalid CSS' do
        let(:admin) { create(:user, :admin) }
        let(:brand_settings) { { brand_settings: { custom_css: '<script>alert(1)</script>' } } }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 errors: { type: :array, items: { type: :string } },
               }
        run_test!
      end

      response '403', 'forbidden for non-admin users' do
        let(:user) { create(:user) }
        let(:brand_settings) { { brand_settings: { custom_css: '' } } }

        before { sign_in user }

        schema type: :object,
               properties: {
                 error: { type: :string },
               }
        run_test!
      end
    end
  end
end
