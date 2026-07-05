require 'swagger_helper'

# == Email Template Designs API
#
# Read-only gallery of predefined, ready-to-use email designs surfaced in the
# "Choose a Template" step of the Email Engine's New Template flow. Selecting
# one prefills subject/html_body/text_body so admins can start from a
# polished, email-client-safe layout instead of a blank editor.
RSpec.describe 'Admin::EmailTemplateDesigns', type: :request do
  path '/admin/email_templates/design_templates' do
    get 'Lists the predefined email design gallery' do
      tags 'Admin - Email Templates'
      produces 'application/json'
      security [ Bearer: [] ]

      response '200', 'design gallery retrieved successfully' do
        let(:admin) { create(:user, :admin) }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 designs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string },
                       name: { type: :string },
                       category: { type: :string },
                       description: { type: :string },
                       subject: { type: :string },
                       html_body: { type: :string },
                       text_body: { type: :string },
                     },
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
  end
end
