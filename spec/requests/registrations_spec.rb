# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account" do
  let(:current_password) { Faker::Internet.password }
  let(:user) { create :user, password: current_password }

  describe "POST /signup" do
    it "creates an unverified user without returning tokens" do
      post "/signup",
           params: {login: "new@example.com", password: "securepass", name: "New User"},
           as:     :json
      expect(response).to have_http_status(:success)
      user = User.find_by!(email: "new@example.com")
      expect(user.name).to eq("New User")
      expect(user.status_id).to eq(1)
      body = response.parsed_body
      expect(body["access_token"]).to be_blank
      expect(body["refresh_token"]).to be_blank
    end

    it "handles validation errors" do
      post "/signup",
           params: {login: "invalid", password: "securepass", name: "Test"},
           as:     :json
      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body["error"]).to be_present
    end
  end

  describe "GET /account" do
    it "requires an authenticated user" do
      get "/account", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "[authenticated]" do
      before(:each) { sign_in user }

      it "responds with user information" do
        get "/account", as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body["name"]).to eq(user.name)
        expect(body["email"]).to eq(user.email)
        expect(body["venmo_handle"]).to be_nil
        expect(body["passkeys"]).to eq([])
      end
    end
  end

  describe "PUT /account" do
    it "requires an authenticated user" do
      put "/account",
          params: {user: {name: "Updated"}},
          as:     :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "[authenticated]" do
      before(:each) { sign_in user }

      it "updates a user" do
        new_email = "updated@example.com"
        put "/account",
            params: {user: {name: "Updated Name", email: new_email}},
            as:     :json
        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body["name"]).to eq("Updated Name")
        expect(body["email"]).to eq(new_email)
        expect(user.reload.email).to eq(new_email)
      end

      it "updates payment handles" do
        put "/account",
            params: {user: {venmo_handle: "tim-morgan", paypal_handle: "timmorgan", cashapp_cashtag: "$timmy"}},
            as:     :json
        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body["venmo_handle"]).to eq("tim-morgan")
        expect(body["paypal_handle"]).to eq("timmorgan")
        expect(body["cashapp_cashtag"]).to eq("$timmy")
      end

      it "handles validation errors" do
        put "/account",
            params: {user: {email: " "}},
            as:     :json
        expect(response).to have_http_status(:unprocessable_content)
        body = response.parsed_body
        expect(body["errors"]["email"]).to be_present
      end
    end
  end

  describe "DELETE /account" do
    it "requires an authenticated user" do
      delete "/account", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "[authenticated]" do
      before(:each) { sign_in user }

      it "deletes a user" do
        delete "/account", as: :json
        expect(response).to have_http_status(:no_content)
        expect { user.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
