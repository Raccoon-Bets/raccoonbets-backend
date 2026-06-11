# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /login with Turnstile" do
  let(:password) { Faker::Internet.password }
  let(:user) { create :user, password: }

  context "when Turnstile verification succeeds" do
    before(:each) do
      allow(TurnstileVerifier).to receive(:verify).
          and_return(TurnstileVerifier::Result.new(success?: true, error_codes: []))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("cypress"))
    end

    it "logs the user in" do
      expect(TurnstileVerifier).to receive(:verify).with("tok", anything)
      post "/login", params: {login: user.email, password:, turnstile_token: "tok"}, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body["access_token"]).to be_present
    end
  end

  context "when Turnstile verification fails" do
    before(:each) do
      allow(TurnstileVerifier).to receive(:verify).
          and_return(TurnstileVerifier::Result.new(success?: false, error_codes: %w[invalid-input-response]))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("cypress"))
    end

    it "returns 400 and does not issue a token" do
      post "/login", params: {login: user.email, password:, turnstile_token: "bad"}, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["access_token"]).to be_blank
    end

    # The Turnstile check must fire in `before_login_route`, not
    # `before_login`, which Rodauth only runs after a successful password
    # match. Otherwise a bot can POST /login with any email that doesn't
    # exist and get the standard "no matching login" 401 without ever
    # solving the captcha, turning /login into a free account-enumeration
    # oracle.
    it "rejects with captcha error before Rodauth's account lookup runs" do
      post "/login", params: {login: "nobody@example.com", password: "x", turnstile_token: "bad"}, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("captcha verification failed")
    end
  end
end
