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

  describe "push prompt dismissal" do
    it "exposes push_prompt_dismissed_at in the account JSON" do
      sign_in user
      user.update!(push_prompt_dismissed_at: Time.utc(2026, 1, 2, 3, 4, 5))

      get "/account"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["push_prompt_dismissed_at"]).to eq("2026-01-02T03:04:05.000Z")
    end

    it "stamps push_prompt_dismissed_at when dismiss_push_prompt is set" do
      sign_in user

      expect do
        patch "/account", params: {user: {dismiss_push_prompt: true}}
      end.to change { user.reload.push_prompt_dismissed_at }.from(nil)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["push_prompt_dismissed_at"]).to be_present
    end

    it "leaves push_prompt_dismissed_at unset when dismiss_push_prompt is absent" do
      sign_in user

      patch "/account", params: {user: {name: "Renamed"}}

      expect(user.reload.push_prompt_dismissed_at).to be_nil
    end
  end
end
