# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /signup with Turnstile" do
  let(:params) { {login: "tsig@example.com", password: "securepass", name: "Tee", turnstile_token: "tok"} }

  context "when Turnstile verification succeeds" do
    before(:each) do
      allow(TurnstileVerifier).to receive(:verify).
          and_return(TurnstileVerifier::Result.new(success?: true, error_codes: []))
      # Force the rodauth hook out of test-bypass mode for this example.
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("cypress"))
    end

    it "creates the account" do
      expect(TurnstileVerifier).to receive(:verify).with("tok", anything)
      post "/signup", params: params, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  context "when Turnstile verification fails" do
    before(:each) do
      allow(TurnstileVerifier).to receive(:verify).
          and_return(TurnstileVerifier::Result.new(success?: false, error_codes: %w[invalid-input-response]))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("cypress"))
    end

    it "returns 400 and does not create the account" do
      expect do
        post "/signup", params: params, as: :json
      end.not_to change(User, :count)
      expect(response).to have_http_status(:bad_request)
      body = response.parsed_body
      expect(body["error"] || body["field-error"]).to be_present
    end

    # The Turnstile check must fire in `before_create_account_route`, not
    # `before_create_account`, which Rodauth only runs after all signup
    # validations pass. Otherwise a bot can POST /signup with an
    # already-taken email and get a 422 "already an account" response
    # without ever solving the captcha, turning /signup into an
    # enumeration oracle for known accounts.
    it "rejects with captcha error before Rodauth's already-taken check runs" do
      existing = create :user
      dup_params = {login: existing.email, password: "securepass", name: "Dup", turnstile_token: "bad"}
      post "/signup", params: dup_params, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("captcha verification failed")
    end
  end
end
