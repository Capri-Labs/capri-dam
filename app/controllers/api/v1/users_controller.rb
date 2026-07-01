module Api
  module V1
    class UsersController < ApplicationController
      before_action :authenticate_hybrid!

      def index
        scope = User.order(:first_name, :last_name, :email)
        if params[:q].present?
          q = "%#{params[:q].strip.downcase}%"
          scope = scope.where(
            "LOWER(username) LIKE :q OR LOWER(email) LIKE :q OR LOWER(first_name) LIKE :q OR LOWER(last_name) LIKE :q OR LOWER(name) LIKE :q",
            q: q
          )
        end

        users = scope.limit(10)
        render json: {
          users: users.map do |user|
            {
              id: user.id,
              username: user.username,
              name: user.full_name,
              email: user.email,
            }
          end,
        }
      end
    end
  end
end
