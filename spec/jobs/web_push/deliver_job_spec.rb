# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebPush::DeliverJob do
  let(:subscription) { create(:push_subscription) }
  let(:payload) { {title: "Hi", body: "There", url: "https://example.com"} }

  it "sends via WebPush with the stored keys and VAPID config" do
    expect(WebPush).to receive(:payload_send).with(
      hash_including(endpoint: subscription.endpoint, p256dh: subscription.p256dh_key, auth: subscription.auth_key)
    )
    described_class.perform_now(subscription.id, payload)
  end

  it "deletes the subscription when the endpoint is gone" do
    fake_response = instance_double(Net::HTTPResponse, code: "410", body: "Gone")
    allow(WebPush).to receive(:payload_send).and_raise(
      WebPush::ExpiredSubscription.new(fake_response, "push.example.com")
    )
    described_class.perform_now(subscription.id, payload)
    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end

  it "no-ops if the subscription is already gone" do
    expect { described_class.perform_now(-1, payload) }.not_to raise_error
  end
end
