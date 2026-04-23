require 'rails_helper'

RSpec.describe "Users::Sessions", type: :request do
  # We create the user once. We can access its attributes via the 'user' variable.
  let(:user) { create(:user, password: "password123") }

  describe "POST /users/sign_in.json" do
    it "returns success on valid login" do
      post "/users/sign_in.json",
           params: {
             user: {
               email: user.email,
               password: "password123"
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["success"]).to eq(true)
      expect(json["user"]["email"]).to eq(user.email)
    end

    it "returns unauthorized on invalid password" do
      post "/users/sign_in.json",
           params: {
             user: {
               email: user.email,
               password: "wrong_password"
             }
           },
           as: :json

      expect(response).to have_http_status(:unauthorized)

      json = JSON.parse(response.body)
      expect(json["success"]).to eq(false)
      expect(json["error"]).to eq("Invalid email or password")
    end
  end
end