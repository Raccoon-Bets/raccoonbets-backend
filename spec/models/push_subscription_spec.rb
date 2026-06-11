# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushSubscription do
  it "belongs to a user and requires endpoint + keys" do
    sub = build(:push_subscription, endpoint: nil)
    expect(sub).not_to be_valid
    expect(sub.errors[:endpoint]).to be_present
  end

  it "enforces endpoint uniqueness" do
    existing = create(:push_subscription)
    dup = build(:push_subscription, endpoint: existing.endpoint)
    expect(dup).not_to be_valid
  end

  describe "#keys_match?" do
    let(:sub) { build(:push_subscription, p256dh_key: "pub", auth_key: "secret") }

    it "is true only when both keys match" do
      expect(sub.keys_match?(p256dh: "pub", auth: "secret")).to be(true)
      expect(sub.keys_match?(p256dh: "pub", auth: "wrong")).to be(false)
      expect(sub.keys_match?(p256dh: "wrong", auth: "secret")).to be(false)
      expect(sub.keys_match?(p256dh: nil, auth: nil)).to be(false)
    end
  end
end
