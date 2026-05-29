require 'swagger_helper'

RSpec.describe 'Api::V1::Notifications', type: :request do
  path '/api/v1/notifications' do
    # 1. GET /api/v1/notifications
    get 'Retrieves recent unread notifications for the current user' do
      tags 'Notifications'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'notifications retrieved successfully' do
        schema type: :array,
               items: {
                 type: :object,
                 properties: {
                   id: { type: :integer },
                   message: { type: :string, description: 'The notification text/content' },
                   read_at: { type: :string, format: 'date-time', nullable: true },
                   created_at: { type: :string, format: 'date-time' }
                   # Note: Add any other fields your Notification model serializes (e.g., action_url, type)
                 }
               }
        run_test!
      end
    end
  end

  path '/api/v1/notifications/mark_all_read' do
    # 2. PATCH /api/v1/notifications/mark_all_read
    patch 'Marks all unread notifications as read' do
      tags 'Notifications'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'all notifications marked as read successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean }
               }
        run_test!
      end
    end
  end

  path '/api/v1/notifications/{id}/mark_read' do
    parameter name: :id, in: :path, type: :string, description: 'Notification ID'

    # 3. PATCH /api/v1/notifications/:id/mark_read
    patch 'Marks a specific notification as read' do
      tags 'Notifications'
      produces 'application/json'
      security [Bearer: []]

      response '200', 'notification marked as read successfully' do
        schema type: :object,
               properties: {
                 success: { type: :boolean }
               }
        run_test!
      end

      response '404', 'notification not found' do
        schema type: :object,
               properties: {
                 error: { type: :string }
               }
        run_test!
      end
    end
  end
end