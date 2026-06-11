# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OmniAuth social login" do
  let(:frontend) { Rails.application.config.urls.frontend }

  before(:each) { OmniAuth.config.test_mode = true }

  after(:each) do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google] = nil
  end

  def mock_google(email:, uid: "google-uid-123", name: "Ada Lovelace")
    OmniAuth.config.mock_auth[:google] = OmniAuth::AuthHash.new(
        provider: "google",
        uid:      uid,
        info:     {email:, name:}
      )
  end

  # Drives the full browser flow: the request-phase POST redirects to the
  # provider callback, which logs in and redirects back to the SPA.
  def sign_in_with_google(origin: frontend)
    post "/auth/google", params: {origin:}
    follow_redirect!
  end

  # The callback hands tokens to the SPA in the redirect fragment.
  def callback_tokens
    fragment = URI.parse(response.location).fragment.to_s
    Rack::Utils.parse_nested_query(fragment)
  end

  describe "a brand-new identity" do
    before(:each) { mock_google(email: "newcomer@example.com") }

    it "creates a verified, passwordless account and links the identity" do
      expect { sign_in_with_google }.to change(User, :count).by(1)

      user = User.find_by!(email: "newcomer@example.com")
      expect(user.status_id).to eq(2) # open / verified, bypassing email verification
      expect(user.name).to eq("Ada Lovelace")
      expect(user.password_hash).to be_nil
      expect(user.identities.pluck(:provider, :uid)).to eq([%w[google google-uid-123]])
    end

    it "redirects to the SPA callback with a refreshable token pair" do
      sign_in_with_google

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("#{frontend}/oauth/callback#")

      tokens = callback_tokens
      expect(tokens["access_token"]).to be_present
      expect(tokens["refresh_token"]).to be_present

      payload, = JWT.decode(tokens["access_token"], Rails.application.credentials.jwt_secret, true, algorithm: "HS256")
      expect(payload["e"]).to eq("newcomer@example.com")

      # The minted access token authenticates a normal JSON request...
      get "/account", headers: {"Authorization" => "Bearer #{tokens["access_token"]}"}
      expect(response).to have_http_status(:success)

      # ...and the refresh token exchanges for a fresh one.
      post "/jwt-refresh",
           params:  {refresh_token: tokens["refresh_token"]},
           headers: {"Authorization" => "Bearer #{tokens["access_token"]}"},
           as:      :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body["access_token"]).to be_present
    end

    it "does not require a Turnstile token" do
      expect { sign_in_with_google }.to change(User, :count).by(1)
      expect(response.location).to start_with("#{frontend}/oauth/callback#")
    end
  end

  describe "matching an existing account by verified email" do
    it "links to a verified password account without creating a new user" do
      user = create :user, email: "ada@example.com"
      mock_google(email: "ada@example.com")

      expect { sign_in_with_google }.not_to change(User, :count)
      expect(user.identities.count).to eq(1)
      expect(callback_tokens["access_token"]).to be_present
    end

    it "verifies a previously unverified account" do
      user = create :user, :unverified, email: "pending@example.com"
      mock_google(email: "pending@example.com")

      sign_in_with_google

      expect(user.reload.status_id).to eq(2)
      expect(callback_tokens["access_token"]).to be_present
    end
  end

  describe "the redirect origin" do
    before(:each) { mock_google(email: "newcomer@example.com") }

    it "falls back to the apex frontend when the origin is untrusted" do
      sign_in_with_google(origin: "https://evil.example.com")
      expect(response.location).to start_with("#{frontend}/oauth/callback#")
    end
  end
end
