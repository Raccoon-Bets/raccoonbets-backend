# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "venmo_handle" do
    it "accepts valid handles" do
      %w[abcde tim-morgan user_name 0racoons aA9-_zZ].each do |handle|
        expect(build(:user, venmo_handle: handle)).to be_valid
      end
    end

    it "rejects malformed handles" do
      ["abcd", "a" * 31, "has space", "dots.dots", "bang!"].each do |handle|
        user = build(:user, venmo_handle: handle)
        expect(user).not_to be_valid
        expect(user.errors).to be_of_kind(:venmo_handle, :invalid)
      end
    end

    it "strips a pasted @ and surrounding whitespace" do
      user = build(:user, venmo_handle: " @tim-morgan ")
      expect(user.venmo_handle).to eq("tim-morgan")
      expect(user).to be_valid
    end
  end

  describe "paypal_handle" do
    it "accepts alphanumeric handles" do
      %w[a timmorgan ABC123 0racoons].each do |handle|
        expect(build(:user, paypal_handle: handle)).to be_valid
      end
    end

    it "rejects handles with symbols, dashes, or that are too long" do
      ["tim-morgan", "tim morgan", "tim.morgan", "a" * 21].each do |handle|
        user = build(:user, paypal_handle: handle)
        expect(user).not_to be_valid
        expect(user.errors).to be_of_kind(:paypal_handle, :invalid)
      end
    end

    it "strips a pasted paypal.me/ prefix" do
      user = build(:user, paypal_handle: "paypal.me/timmorgan")
      expect(user.paypal_handle).to eq("timmorgan")
      expect(user).to be_valid
    end
  end

  describe "cashapp_cashtag" do
    it "accepts cashtags containing at least one letter" do
      %w[timmy a r2d2 cash-tag cash_tag].each do |cashtag|
        expect(build(:user, cashapp_cashtag: cashtag)).to be_valid
      end
    end

    it "rejects digit-only, too-long, or otherwise malformed cashtags" do
      ["12345", "a" * 21, "has space", "dots.dots"].each do |cashtag|
        user = build(:user, cashapp_cashtag: cashtag)
        expect(user).not_to be_valid
        expect(user.errors).to be_of_kind(:cashapp_cashtag, :invalid)
      end
    end

    it "strips a pasted $ sigil" do
      user = build(:user, cashapp_cashtag: " $timmy ")
      expect(user.cashapp_cashtag).to eq("timmy")
      expect(user).to be_valid
    end
  end

  it "leaves blank handles nil" do
    user = build(:user, venmo_handle: "  ", paypal_handle: "", cashapp_cashtag: " $ ")
    expect(user.venmo_handle).to be_nil
    expect(user.paypal_handle).to be_nil
    expect(user.cashapp_cashtag).to be_nil
    expect(user).to be_valid
  end
end
