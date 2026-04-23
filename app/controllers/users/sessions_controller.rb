# app/controllers/users/sessions_controller.rb
class Users::SessionsController < Devise::SessionsController
  respond_to :json

  def create
    # 1. Manually find the user by email
    resource = User.find_for_database_authentication(email: params[:user][:email])

    # 2. Check if the user exists and the password is correct
    if resource&.valid_password?(params[:user][:password])
      sign_in(:user, resource)
      render json: {
        success: true,
        user: { email: resource.email, username: resource.username }
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Invalid email or password"
      }, status: :unauthorized
    end
  end
end