# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/markets" do
  include ActiveJob::TestHelper

  let(:group) { create :group }
  let(:membership) { create :membership, group: }
  let(:member) { membership.user }
  let(:outsider) { create :user }

  describe "GET /" do
    it "rejects non-members" do
      sign_in outsider
      get "/groups/#{group.to_param}/markets.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "filters open markets past their lock time with status=locked" do
      create(:market, group:) # open, with a future locks_at
      locked = create(:market, :locked, group:)
      create(:market, :resolved, group:)

      sign_in member
      get "/groups/#{group.to_param}/markets.json", params: {status: "locked"}

      expect(response).to be_successful
      expect(response.parsed_body.pluck("id")).to eq([locked.id])
    end

    it "includes per-outcome pool totals and the member's own position" do
      market   = create(:market, group:)
      yes, no  = market.outcomes.to_a
      create(:position, market:, outcome: yes, amount_cents: 100)
      create(:position, market:, outcome: yes, amount_cents: 200)
      my_position = create(:position, market:, outcome: no, membership:, amount_cents: 50)

      sign_in member
      get "/groups/#{group.to_param}/markets.json"

      expect(response).to be_successful
      expect(response.body).to match_json([{
                                              id:                      market.id,
                                              title:                   String,
                                              status:                  "open",
                                              kind:                    "scheduled",
                                              locks_at:                String,
                                              created_at:              String,
                                              winning_outcome_id:      nil,
                                              resolved_at:             nil,
                                              resolution_effective_at: nil,
                                              locked:                  false,
                                              currency:                "USD",
                                              creator:                 {id: Integer, name: String},
                                              oracle:                  {id: Integer, name: String},
                                              total_pool_cents:        350,
                                              outcomes:                [
                                                  {id: yes.id, name: "YES", position: 0, pool_cents: 300, position_count: 2},
                                                  {id: no.id, name: "NO", position: 1, pool_cents: 50, position_count: 1}
                                              ],
                                              my_position:             {id: my_position.id, outcome_id: no.id, amount_cents: 50}
                                          }])
    end
  end

  describe "POST /" do
    it "rejects non-members" do
      sign_in outsider
      post "/groups/#{group.to_param}/markets.json",
           params: {market: {title: "Test?", locks_at: 1.day.from_now, outcomes: %w[YES NO]}}
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a market with outcomes positioned by array order, defaulting the oracle to the creator" do
      sign_in member
      post "/groups/#{group.to_param}/markets.json",
           params: {market: {title: "Who wins the bake-off?", locks_at: 1.day.from_now,
                             outcomes: %w[Red Green Blue]}}

      expect(response).to be_successful
      market = group.markets.sole
      expect(market.creator).to eq(membership)
      expect(market.oracle).to eq(membership)
      expect(market.outcomes.pluck(:name, :position)).to eq([["Red", 0], ["Green", 1], ["Blue", 2]])
    end

    it "rejects an oracle from another group" do
      sign_in member
      post "/groups/#{group.to_param}/markets.json",
           params: {market: {title: "Test?", locks_at: 1.day.from_now, oracle_id: create(:membership).id,
                             outcomes: %w[YES NO]}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(group.markets).to be_empty
    end
  end

  describe "DELETE /:id" do
    let(:admin_membership) { create :membership, :admin, group: }
    let(:market) { create :market, group: }

    it "rejects non-admin members" do
      sign_in member
      delete "/groups/#{group.to_param}/markets/#{market.id}.json"

      expect(response).to have_http_status(:forbidden)
      expect(Market.exists?(market.id)).to be(true)
    end

    it "deletes an unresolved market, cascading positions and mailing the other holders" do
      holder = create(:position, market:).membership.user
      create(:position, market:, membership: admin_membership)

      ActionMailer::Base.deliveries.clear
      sign_in admin_membership.user
      perform_enqueued_jobs do
        delete "/groups/#{group.to_param}/markets/#{market.id}.json"
      end

      expect(response).to have_http_status(:no_content)
      expect(Market.exists?(market.id)).to be(false)
      expect(Position.count).to eq(0)
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly(holder.email)
    end

    it "rejects deleting a market whose money has moved" do
      yes, no = market.outcomes.to_a
      create(:position, market:, outcome: yes)
      create(:position, market:, outcome: no)
      market.update_column(:locks_at, 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      Markets::Resolver.resolve(market, yes, market.oracle)

      sign_in admin_membership.user
      delete "/groups/#{group.to_param}/markets/#{market.id}.json"

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("errors", "base")).to be_present
      expect(Market.exists?(market.id)).to be(true)
    end
  end

  describe "PATCH /:id" do
    let(:market) { create :market, group: }

    it "rejects members other than the creator" do
      sign_in member
      patch "/groups/#{group.to_param}/markets/#{market.id}.json",
            params: {market: {title: "Hijacked?"}}

      expect(response).to have_http_status(:forbidden)
      expect(market.reload.title).not_to eq("Hijacked?")
    end

    it "rejects edits once the market is no longer open" do
      voided = create(:market, :voided, group:, creator: membership, oracle: membership)
      sign_in member
      patch "/groups/#{group.to_param}/markets/#{voided.id}.json",
            params: {market: {title: "Too late?"}}

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets the creator edit the title while open" do
      mine = create(:market, group:, creator: membership, oracle: membership)
      sign_in member
      patch "/groups/#{group.to_param}/markets/#{mine.id}.json",
            params: {market: {title: "Clarified?"}}

      expect(response).to be_successful
      expect(mine.reload.title).to eq("Clarified?")
    end

    it "lets a group admin edit another member's open market, mailing the other holders" do
      admin_membership = create(:membership, :admin, group:)
      market.update_column(:closing_soon_notified_at, 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      holder = create(:position, market:).membership.user
      create(:position, market:, membership: admin_membership)
      new_locks_at = 3.days.from_now.change(usec: 0)

      ActionMailer::Base.deliveries.clear
      sign_in admin_membership.user
      perform_enqueued_jobs do
        patch "/groups/#{group.to_param}/markets/#{market.id}.json",
              params: {market: {title: "Clarified by an admin?", locks_at: new_locks_at.iso8601}}
      end

      expect(response).to be_successful
      expect(market.reload.title).to eq("Clarified by an admin?")
      expect(market.locks_at).to be_within(1.second).of(new_locks_at)
      expect(market.closing_soon_notified_at).to be_nil
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly(holder.email)
      expect(ActionMailer::Base.deliveries.first.subject).to include("Clarified by an admin?")
    end
  end
end
