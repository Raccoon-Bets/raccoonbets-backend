# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarketChannel do
  let(:group) { create :group }
  let(:market) { create :market, group: }
  let(:user) { create :user }

  before(:each) { stub_connection current_user: user }

  context "[active member]" do
    before(:each) { create :membership, group:, user: }

    it "confirms the subscription and streams for the market" do
      subscribe id: market.id
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(market)
    end
  end

  context "[non-member]" do
    it "rejects the subscription" do
      subscribe id: market.id
      expect(subscription).to be_rejected
    end
  end

  context "[member of a different group]" do
    before(:each) { create :membership, user: }

    it "rejects the subscription" do
      subscribe id: market.id
      expect(subscription).to be_rejected
    end
  end

  context "[unknown market]" do
    it "rejects the subscription" do
      subscribe id: -1
      expect(subscription).to be_rejected
    end
  end
end
