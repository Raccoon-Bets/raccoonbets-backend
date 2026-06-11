# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/markets/:market_id/resolution" do
  let(:group) { create :group }
  let(:admin) { create :membership, :admin, group: }
  let(:oracle) { create :membership, group: }
  let(:member) { create :membership, group: }
  let(:market) { create :market, group:, oracle: }
  let(:outcome) { market.outcomes.first }
  let(:path) { "/groups/#{group.to_param}/markets/#{market.id}/resolution.json" }

  def lock!(market)
    market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
  end

  describe "POST /" do
    it "rejects non-members" do
      sign_in create(:user)
      post path, params: {outcome_id: outcome.id}
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects members who are neither the oracle nor an admin" do
      sign_in member.user
      post path, params: {outcome_id: outcome.id}
      expect(response).to have_http_status(:forbidden)
      expect(market.reload).to be_open
    end

    it "lets the oracle resolve, responding with the market detail" do
      create(:position, market:, outcome:, amount_cents: 100)
      create(:position, market:, outcome: market.outcomes.second, amount_cents: 100)
      lock! market

      sign_in oracle.user
      post path, params: {outcome_id: outcome.id}

      expect(response).to be_successful
      expect(response.parsed_body).to include("status" => "resolved", "winning_outcome_id" => outcome.id)
      expect(response.parsed_body["payouts"]).to contain_exactly(
          a_hash_including("net_cents" => 100), a_hash_including("net_cents" => -100)
        )
      expect(response.parsed_body["events"]).to contain_exactly(a_hash_including("action" => "resolved"))
      expect(group).to have_zero_sum_ledger
    end

    it "maps resolver errors to 422" do
      sign_in oracle.user
      post path, params: {outcome_id: outcome.id}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("before trading closes")
    end
  end

  describe "PUT /" do
    before(:each) do
      lock! market
      Markets::Resolver.resolve market, outcome, oracle
    end

    it "rejects the oracle when they are not an admin" do
      sign_in oracle.user
      put path, params: {outcome_id: market.outcomes.second.id}
      expect(response).to have_http_status(:forbidden)
      expect(market.reload.winning_outcome).to eq(outcome)
    end

    it "lets an admin correct to another outcome" do
      sign_in admin.user
      put path, params: {outcome_id: market.outcomes.second.id}

      expect(response).to be_successful
      expect(market.reload.winning_outcome).to eq(market.outcomes.second)
      expect(group).to have_zero_sum_ledger
    end
  end

  describe "DELETE /" do
    it "rejects members who are neither the oracle nor an admin" do
      sign_in member.user
      delete path
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the oracle void" do
      sign_in oracle.user
      delete path

      expect(response).to be_successful
      expect(market.reload).to be_voided
    end

    it "lets an admin void a resolved market, reversing its entries" do
      create(:position, market:, outcome:, amount_cents: 100)
      create(:position, market:, outcome: market.outcomes.second, amount_cents: 100)
      lock! market
      Markets::Resolver.resolve market, outcome, oracle

      sign_in admin.user
      delete path

      expect(response).to be_successful
      expect(market.reload).to be_voided
      expect(group).to have_zero_sum_ledger
      expect(market.ledger_entries.reversal.count).to eq(2)
    end
  end
end
