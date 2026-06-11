# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationMailer do
  let(:group) { create(:group, subdomain: "trash-pandas") }
  let(:user) { create(:user) }
  let(:market) { create(:market, group:, title: "Will it rain?") }

  it "renders market_resolved with a link to the market and the localized kind" do
    mail = described_class.market_resolved(user:, market:, kind: "corrected")
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to be_present
    expect(mail.body.encoded).to include("/markets/#{market.id}")
    expect(mail.body.encoded).to include("corrected")
    expect(mail.body.encoded).not_to include("translation missing")
  end

  it "renders market_closing_soon" do
    mail = described_class.market_closing_soon(user:, market:)
    expect(mail.to).to eq([user.email])
    expect(mail.body.encoded).to include(market.title)
  end

  it "renders settlement with the localized kind" do
    settlement = create(:settlement, group:)
    mail = described_class.settlement(user:, settlement:, kind: "recorded")
    expect(mail.to).to eq([user.email])
    expect(mail.body.encoded).to include("recorded")
    expect(mail.body.encoded).not_to include("translation missing")
  end
end
