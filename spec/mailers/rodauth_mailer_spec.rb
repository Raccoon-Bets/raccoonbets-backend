# frozen_string_literal: true

require "rails_helper"

RSpec.describe RodauthMailer do
  let(:email) { "user@example.com" }
  let(:link)  { "https://raccoonbets.org/verify-account?key=abc123" }

  shared_examples "a multipart email" do |subject|
    it "sets the recipient and subject" do
      expect(mail.to).to eq([email])
      expect(mail.subject).to eq(subject)
      expect(mail.from).to eq(["donotreply@raccoonbets.org"])
    end

    it "is multipart with text/plain and text/html parts" do
      expect(mail).to be_multipart
      content_types = mail.parts.map(&:content_type)
      expect(content_types.any? { |t| t.start_with?("text/plain") }).to be true
      expect(content_types.any? { |t| t.start_with?("text/html") }).to be true
    end

    it "includes the link as an <a href> in the HTML part" do
      html_part = mail.parts.find { |p| p.content_type.start_with?("text/html") }
      expect(html_part.body.decoded).to include(%(href="#{link}"))
    end

    it "includes the link as a plain URL in the text part" do
      text_part = mail.parts.find { |p| p.content_type.start_with?("text/plain") }
      expect(text_part.body.decoded).to include(link)
    end
  end

  describe "#verify_account" do
    let(:mail) { described_class.verify_account(email, link) }

    it_behaves_like "a multipart email", "Verify your Raccoon Bets account"
  end

  describe "#reset_password" do
    let(:mail) { described_class.reset_password(email, link) }

    it_behaves_like "a multipart email", "Reset your Raccoon Bets password"
  end
end
