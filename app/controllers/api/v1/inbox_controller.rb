module Api
  module V1
    class InboxController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :set_message, only: %i[show mark_read mark_unread archive star destroy]

      def index
        scope = current_user.inbox_messages.active.recent
        scope = scope.by_type(params[:type]) if params[:type].present?
        scope = scope.unread if ActiveModel::Type::Boolean.new.cast(params[:unread_only])
        scope = scope.starred if ActiveModel::Type::Boolean.new.cast(params[:starred_only])

        per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        total = scope.count
        messages = scope.offset((page - 1) * per_page).limit(per_page)

        render json: {
          messages: messages.map { |message| serialize_message(message) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil,
          },
          unread_count: current_user.inbox_messages.active.unread.count,
        }
      end

      def show
        @message.mark_read!
        render json: { message: serialize_message(@message, full: true) }
      end

      def mark_read
        @message.mark_read!
        render json: { success: true, unread_count: current_user.inbox_messages.active.unread.count }
      end

      def mark_unread
        @message.mark_unread!
        render json: { success: true, unread_count: current_user.inbox_messages.active.unread.count }
      end

      def mark_all_read
        current_user.inbox_messages.active.unread.update_all(read_at: Time.current)
        render json: { success: true, unread_count: 0 }
      end

      def archive
        @message.archive!
        render json: { success: true }
      end

      def star
        @message.star!
        render json: { success: true, starred: @message.starred? }
      end

      def destroy
        @message.destroy!
        render json: { success: true }
      end

      def unread_count
        render json: { unread_count: current_user.inbox_messages.active.unread.count }
      end

      private

      def set_message
        @message = current_user.inbox_messages.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Message not found" }, status: :not_found
      end

      def serialize_message(message, full: false)
        data = {
          id: message.id,
          subject: message.subject,
          message_type: message.message_type,
          read: message.read?,
          starred: message.starred?,
          created_at: message.created_at.iso8601,
          sender: serialize_sender(message.sender),
          snippet: message.body_text.present? ? helpers.truncate(message.body_text, length: 150) : nil,
        }

        return data unless full

        data.merge(
          body_html: message.body_html,
          body_text: message.body_text,
          metadata: message.metadata
        )
      end

      def serialize_sender(sender)
        return nil unless sender

        {
          id: sender.id,
          name: sender.full_name,
          email: sender.email,
        }
      end
    end
  end
end
