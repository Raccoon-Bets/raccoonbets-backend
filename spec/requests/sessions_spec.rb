# frozen_string_literal: true

require "rails_helper"

RSpec.describe "sessions" do
  let(:password) { Faker::Internet.password }
  let(:user) { create :user, password: }
  let(:email) { user.email }

  describe "POST /login" do
    it "returns user data and tokens on success" do
      post "/login",
           params: {login: email, password:},
           as:     :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body["name"]).to eq(user.name)
      expect(body["email"]).to eq(user.email)
      expect(body["passkeys"]).to eq([])
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(response.headers["Authorization"]).to be_present
    end

    it "returns an error if the email does not exist" do
      post "/login",
           params: {login: "wrong@example.com", password:},
           as:     :json
      expect(response).to have_http_status(:unauthorized)
      body = response.parsed_body
      expect(body["error"]).to be_present
    end

    it "returns an error if the password is incorrect" do
      post "/login",
           params: {login: email, password: "wrong"},
           as:     :json
      expect(response).to have_http_status(:unauthorized)
      body = response.parsed_body
      expect(body["error"]).to be_present
    end
  end

  describe "POST /jwt-refresh" do
    it "exchanges a refresh token for a new access token" do
      post "/login", params: {login: email, password:}, as: :json
      body = response.parsed_body
      access_token = body["access_token"]
      refresh_token = body["refresh_token"]

      post "/jwt-refresh",
           params:  {refresh_token:},
           headers: {"Authorization" => "Bearer #{access_token}"},
           as:      :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(body["access_token"]).not_to eq(access_token)
    end

    it "rejects an invalid refresh token" do
      post "/login", params: {login: email, password:}, as: :json
      access_token = response.parsed_body["access_token"]

      post "/jwt-refresh",
           params:  {refresh_token: "bogus"},
           headers: {"Authorization" => "Bearer #{access_token}"},
           as:      :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /logout" do
    it "returns success when authenticated" do
      post "/logout",
           headers: {"Authorization" => "Bearer #{jwt_for(user)}"},
           as:      :json
      expect(response).to have_http_status(:success)
    end
  end
end
