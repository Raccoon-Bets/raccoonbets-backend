# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/password-resets" do
  let(:user) { create :user }

  describe "POST /password-resets" do
    it "sends a password-reset email" do
      post "/password-resets",
           params: {login: user.email},
           as:     :json
      expect(response).to have_http_status(:no_content)
      expect(ActionMailer::Base.deliveries.last).to be_present
    end

    it "returns 204 even if the email does not exist" do
      post "/password-resets",
           params: {login: "nonexistent@example.com"},
           as:     :json
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /reset-password" do
    before(:each) do
      post "/password-resets",
           params: {login: user.email},
           as:     :json
      mail   = ActionMailer::Base.deliveries.last
      body   = mail.text_part&.body&.decoded || mail.html_part&.body&.decoded || mail.body.decoded
      @token = body.match(/key=([^\s"<]+)/)[1]
    end

    it "resets the password" do
      post "/reset-password",
           params: {key: @token, password: "newpass1!"},
           as:     :json
      expect(response).to have_http_status(:success)
      expect { user.reload }.to change(user, :password_hash)
    end

    it "rejects an invalid token" do
      post "/reset-password",
           params: {key: "invalid_token", password: "newpass1!"},
           as:     :json
      expect(response).to have_http_status(:unauthorized)
      expect { user.reload }.not_to change(user, :password_hash)
    end
  end
end
