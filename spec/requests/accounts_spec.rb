# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts", type: :request do
  let(:user) { create(:user) }

  it "exposes normalized notification preferences and the VAPID public key" do
    sign_in user
    get "/account"
    body = response.parsed_body
    expect(body["notification_preferences"]["market_resolved"]).to eq("email" => true, "push" => true)
    expect(body["vapid_public_key"]).to eq(Rails.application.credentials.dig(:vapid, :public_key))
  end

  it "persists sanitized notification preferences" do
    sign_in user
    patch "/account",
          params: {user: {notification_preferences: {market_created: {email: false}, bogus: {email: true}}}}
    expect(response).to have_http_status(:ok)
    expect(user.reload.notification_preferences).to eq("market_created" => {"email" => false})
  end
end
