# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PushSubscriptions", type: :request do
  let(:user) { create(:user) }
  let(:payload) do
    {endpoint: "https://push.example.com/abc", keys: {p256dh: "key", auth: "secret"}, user_agent: "UA"}
  end

  it "upserts a subscription scoped to the current user" do
    sign_in user
    expect do
      post "/account/push_subscriptions", params: payload
    end.to change { user.push_subscriptions.count }.by(1)
    expect(response).to have_http_status(:no_content)

    # Same endpoint again updates rather than duplicating.
    expect do
      post "/account/push_subscriptions", params: payload.merge(user_agent: "UA2")
    end.not_to change(PushSubscription, :count)
    expect(user.push_subscriptions.sole.user_agent).to eq("UA2")
  end

  it "re-homes a shared-device endpoint when the request proves possession of the channel keys" do
    other = create(:user)
    create(:push_subscription, user: other, endpoint: payload[:endpoint],
                               p256dh_key: payload[:keys][:p256dh], auth_key: payload[:keys][:auth])
    sign_in user

    expect do
      post "/account/push_subscriptions", params: payload
    end.not_to change(PushSubscription, :count)
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.find_by(endpoint: payload[:endpoint]).user).to eq(user)
  end

  it "refuses to take over an endpoint when the request does not have the stored channel keys" do
    other = create(:user)
    create(:push_subscription, user: other, endpoint: payload[:endpoint],
                               p256dh_key: "victim-p256dh", auth_key: "victim-auth")
    sign_in user

    expect do
      post "/account/push_subscriptions", params: payload
    end.not_to change(PushSubscription, :count)
    expect(response).to have_http_status(:forbidden)
    expect(PushSubscription.find_by(endpoint: payload[:endpoint]).user).to eq(other)
  end

  it "deletes by endpoint" do
    create(:push_subscription, user:, endpoint: "https://push.example.com/abc")
    sign_in user
    delete "/account/push_subscriptions", params: {endpoint: "https://push.example.com/abc"}
    expect(response).to have_http_status(:no_content)
    expect(user.push_subscriptions).to be_empty
  end
end
