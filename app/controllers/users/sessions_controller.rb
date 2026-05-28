class Users::SessionsController < Devise::SessionsController
  respond_to :json

  def create
    # 1. Manually find the user by email
    resource = User.find_for_database_authentication(email: params[:user][:email])

    # 2. Check if the user exists and the password is correct
    if resource&.valid_password?(params[:user][:password])

      # 🚨 PHASE 1: Intercept if forced password change is required
      if resource.try(:force_password_change?)
        render json: {
          success: true,
          force_password_change: true,
          email: resource.email
        }, status: :ok
        return
      end

      # Standard Login
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

  # 🚨 NEW: Endpoint to process the mandatory password change
  def force_password_update
    resource = User.find_by(email: params[:email])

    # Re-verify the temporary password to ensure the request is authorized
    if resource&.valid_password?(params[:current_password])
      if resource.update(
        password: params[:new_password],
        password_confirmation: params[:new_password_confirmation],
        force_password_change: false # Clear the flag
      )
        # Automatically sign them in so they don't have to log in twice
        sign_in(:user, resource)

        render json: {
          success: true,
          message: "Password updated successfully.",
          user: { email: resource.email, username: resource.username }
        }, status: :ok
      else
        render json: { success: false, error: resource.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    else
      render json: { success: false, error: "Invalid temporary password." }, status: :unauthorized
    end
  end
end