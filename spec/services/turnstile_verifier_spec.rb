# frozen_string_literal: true

require "rails_helper"

RSpec.describe TurnstileVerifier do
  let(:endpoint) { "https://challenges.cloudflare.com/turnstile/v0/siteverify" }

  describe ".verify" do
    it "returns success when Cloudflare returns success: true" do
      stub_request(:post, endpoint).
          with(body: hash_including("response" => "good-token", "remoteip" => "1.2.3.4")).
          to_return(status: 200, body: {success: true}.to_json)

      result = described_class.verify("good-token", "1.2.3.4")
      expect(result.success?).to be true
      expect(result.error_codes).to eq([])
    end

    it "returns failure with error codes when Cloudflare returns success: false" do
      stub_request(:post, endpoint).
          to_return(status: 200, body: {success: false, "error-codes": %w[invalid-input-response]}.to_json)

      result = described_class.verify("bad-token", "1.2.3.4")
      expect(result.success?).to be false
      expect(result.error_codes).to eq(%w[invalid-input-response])
    end

    it "returns failure with network-error on timeout" do
      stub_request(:post, endpoint).to_timeout

      result = described_class.verify("any-token", "1.2.3.4")
      expect(result.success?).to be false
      expect(result.error_codes).to eq(%w[network-error])
    end

    it "returns failure with missing-input-response when token is blank" do
      result = described_class.verify("", "1.2.3.4")
      expect(result.success?).to be false
      expect(result.error_codes).to eq(%w[missing-input-response])

      result = described_class.verify(nil, "1.2.3.4")
      expect(result.success?).to be false
      expect(result.error_codes).to eq(%w[missing-input-response])
    end

    it "uses Cloudflare's always-passes test secret as a fallback in test env" do
      # No TURNSTILE_SECRET_KEY env var; test env should fall back without raising.
      expect(ENV.fetch("TURNSTILE_SECRET_KEY", nil)).to be_nil
      stub_request(:post, endpoint).
          with(body: hash_including("secret" => "1x0000000000000000000000000000000AA")).
          to_return(status: 200, body: {success: true}.to_json)

      result = described_class.verify("any-token", "1.2.3.4")
      expect(result.success?).to be true
    end
  end
end
