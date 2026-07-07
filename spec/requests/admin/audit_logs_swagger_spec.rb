require 'swagger_helper'

# == Admin Audit Logs API
#
# Read-only viewer for the immutable {AuditLog} trail: every create/update/
# destroy on an {Auditable} model, plus manually recorded administrative
# actions (impersonation grants, etc.). Supports filtering by actor, action,
# resource type, impersonation flag, a created_at date range, and a free-text
# search across actor email / action / resource type.
RSpec.describe 'Admin::AuditLogs', type: :request do
  path '/admin/audit_logs' do
    get 'Lists audit trail entries with filtering and pagination' do
      tags 'Admin - Audit Logs'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :user_id, in: :query, type: :integer, required: false, description: 'Filter by acting user id'
      parameter name: :audit_action, in: :query, type: :string, required: false, description: 'Filter by action (create/update/destroy/...)'
      parameter name: :auditable_type, in: :query, type: :string, required: false, description: 'Filter by audited model class name'
      parameter name: :impersonated, in: :query, type: :boolean, required: false, description: 'Filter to actions taken while impersonating'
      parameter name: :date_from, in: :query, type: :string, required: false, description: 'ISO date lower bound (inclusive)'
      parameter name: :date_to, in: :query, type: :string, required: false, description: 'ISO date upper bound (inclusive)'
      parameter name: :search, in: :query, type: :string, required: false, description: 'Free-text search across actor email / action / resource type'
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      response '200', 'audit logs retrieved successfully' do
        let(:admin) { create(:user, :admin) }

        before do
          sign_in admin
          create(:audit_log, user: admin, action: 'create', auditable_type: 'Folder')
        end

        schema type: :object,
               properties: {
                 audit_logs: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :integer },
                       action: { type: :string },
                       auditable_type: { type: :string },
                       auditable_id: { type: :integer, nullable: true },
                       changes_data: { type: :object, nullable: true },
                       impersonated: { type: :boolean },
                       ip_address: { type: :string, nullable: true },
                       user_agent: { type: :string, nullable: true },
                       created_at: { type: :string },
                       user: { type: :object, nullable: true },
                       true_user: { type: :object, nullable: true },
                     },
                   },
                 },
                 pagination: {
                   type: :object,
                   properties: {
                     page: { type: :integer },
                     per_page: { type: :integer },
                     total: { type: :integer },
                     total_pages: { type: :integer },
                   },
                 },
                 filter_options: {
                   type: :object,
                   properties: {
                     actions: { type: :array, items: { type: :string } },
                     auditable_types: { type: :array, items: { type: :string } },
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
