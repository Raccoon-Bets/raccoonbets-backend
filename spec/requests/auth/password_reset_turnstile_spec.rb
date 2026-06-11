# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /password-resets with Turnstile" do
  let(:user) { create :user }

  context "when Turnstile verification succeeds" do
    before(:each) do
      allow(TurnstileVerifier).to receive(:verify).
          and_return(TurnstileVerifier::Result.new(success?: true, error_codes: []))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("cypress"))
    end

    it "sends a password-reset email" do
      expect(TurnstileVerifier).to receive(:verify).with("tok", anything)
      post "/password-resets", params: {login: user.email, turnstile_token: "tok"}, as: :json
      expect(response).to have_http_status(:no_content)
      expect(ActionMailer::Base.deliveries.last).to be_present
    end
  end

  context "when Turnstile verification fails" do
    before(:each) do
      allow(TurnstileVerifier).to receive(:verify).
          and_return(TurnstileVerifier::Result.new(success?: false, error_codes: %w[invalid-input-response]))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("cypress"))
    end

    it "returns 400 and does not send an email" do
      ActionMailer::Base.deliveries.clear
      post "/password-resets", params: {login: user.email, turnstile_token: "bad"}, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
