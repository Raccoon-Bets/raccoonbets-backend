# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/verify-account" do
  let(:email) { "verify@example.com" }
  let(:password) { "hunter22!" }

  def signup
    post "/signup",
         params: {login: email, password:, name: "Verify Me"},
         as:     :json
  end

  def verification_keys
    ActiveRecord::Base.connection.select_all("SELECT * FROM account_verification_keys")
  end

  def verification_key_count
    verification_keys.count
  end

  def token_from_last_email
    mail = ActionMailer::Base.deliveries.last
    body = mail.text_part&.body&.decoded || mail.html_part&.body&.decoded || mail.body.decoded
    body.match(/key=([^\s"<]+)/)[1]
  end

  describe "POST /signup" do
    it "creates an unverified user and a verification key, with no JWT in the response" do
      expect { signup }.to change(User, :count).by(1).
          and change(self, :verification_key_count).by(1)

      expect(response).to have_http_status(:success)
      user = User.find_by!(email: email)
      expect(user.status_id).to eq(1)

      expect(response.headers["Authorization"]).to be_blank
      expect(response.headers["Refresh-Token"]).to be_blank
      body = response.parsed_body
      expect(body["access_token"]).to be_blank
      expect(body["refresh_token"]).to be_blank

      mail = ActionMailer::Base.deliveries.last
      expect(mail).to be_present
      expect(mail.subject).to eq("Verify your Raccoon Bets account")
      expect(mail.text_part.body.decoded).to include("/verify-account?key=")
      expect(mail.html_part.body.decoded).to include("/verify-account?key=")
    end
  end

  describe "POST /signup (verification email host)" do
    around(:each) do |example|
      original = Rails.application.config.x.frontend_origin_patterns
      Rails.application.config.x.frontend_origin_patterns =
          original + [%r{\Ahttps://([a-z0-9-]+\.)?raccoonbets\.test\z}]
      example.run
    ensure
      Rails.application.config.x.frontend_origin_patterns = original
    end

    def signup_from(origin)
      post "/signup",
           params:  {login: email, password:, name: "Verify Me"},
           headers: {"Origin" => origin},
           as:      :json
    end

    it "links the verification email to a trusted requesting origin" do
      signup_from "https://trash-pandas.raccoonbets.test"

      mail = ActionMailer::Base.deliveries.last
      expect(mail.text_part.body.decoded).
          to include("https://trash-pandas.raccoonbets.test/verify-account?key=")
      expect(mail.html_part.body.decoded).
          to include("https://trash-pandas.raccoonbets.test/verify-account?key=")
    end

    it "falls back to the apex frontend for an untrusted origin" do
      signup_from "https://evil.example.com"

      mail = ActionMailer::Base.deliveries.last
      expect(mail.text_part.body.decoded).to include("http://test.host/verify-account?key=")
    end
  end

  describe "POST /login (unverified)" do
    it "rejects the login with the Rodauth unverified-account error" do
      signup
      user = User.find_by!(email: email)
      expect(user.status_id).to eq(1)

      post "/login",
           params: {login: email, password:},
           as:     :json
      expect(response).to have_http_status(:forbidden)
      body = response.parsed_body
      expect(body["error"]).to be_present
      expect(response.headers["Authorization"]).to be_blank
    end
  end

  describe "POST /verify-account" do
    let(:user) { User.find_by!(email: email) }

    before(:each) { signup }

    it "verifies the account and removes the verification key" do
      post "/verify-account", params: {key: token_from_last_email}, as: :json

      expect(response).to have_http_status(:success)
      expect(user.reload.status_id).to eq(2)
      expect(verification_keys.count).to eq(0)
    end

    it "rejects an invalid key" do
      post "/verify-account", params: {key: "bogus"}, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.status_id).to eq(1)
    end

    it "allows login after verification with a JWT" do
      post "/verify-account", params: {key: token_from_last_email}, as: :json
      expect(response).to have_http_status(:success)

      post "/login", params: {login: email, password:}, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(response.headers["Authorization"]).to be_present
    end
  end
end
