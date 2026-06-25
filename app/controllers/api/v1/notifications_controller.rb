module Api
  module V1
    class NotificationsController < ApplicationController
      before_action :authenticate_user!

      # GET /api/v1/notifications
      def index
        @notifications = current_user.notifications.unread.order(created_at: :desc).limit(10)
        render json: @notifications
      end

      # PATCH /api/v1/notifications/:id/mark_read
      def mark_read
        notification = current_user.notifications.find(params[:id])
        notification.update!(read_at: Time.current)
        render json: { success: true }
      end

      # PATCH /api/v1/notifications/mark_all_read
      def mark_all_read
        current_user.notifications.unread.update_all(read_at: Time.current)
        render json: { success: true }
      end
    end
  end
end
