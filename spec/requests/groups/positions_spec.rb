# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/markets/:market_id/position" do
  include ActiveJob::TestHelper

  let(:group) { create :group }
  let(:membership) { create :membership, group: }
  let(:member) { membership.user }
  let(:market) { create :market, group: }
  let(:path) { "/groups/#{group.to_param}/markets/#{market.id}/position.json" }

  describe "PUT /" do
    it "rejects non-members" do
      sign_in create(:user)
      put path, params: {position: {outcome_id: market.outcomes.first.id, amount_cents: 100}}
      expect(response).to have_http_status(:forbidden)
    end

    it "takes, then changes, the member's single position" do
      yes, no = market.outcomes.to_a
      sign_in member

      put path, params: {position: {outcome_id: yes.id, amount_cents: 100}}
      expect(response).to be_successful

      put path, params: {position: {outcome_id: no.id, amount_cents: 200}}
      expect(response).to be_successful

      position = market.positions.where(membership:).sole
      expect(position.outcome).to eq(no)
      expect(position.amount_cents).to eq(200)
    end

    it "rejects positions once the market is locked" do
      locked = create(:market, :locked, group:)
      sign_in member

      put "/groups/#{group.to_param}/markets/#{locked.id}/position.json",
          params: {position: {outcome_id: locked.outcomes.first.id, amount_cents: 100}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("errors", "base")).to include("trading is closed for this market")
      expect(locked.positions).to be_empty
    end
  end

  describe "DELETE /" do
    it "cancels the member's position before lock" do
      position = create(:position, market:, membership:)
      sign_in member

      delete path
      expect(response).to have_http_status(:no_content)
      expect(Position.exists?(position.id)).to be(false)
    end

    it "refuses to cancel once the market is locked" do
      position = create(:position, market:, membership:)
      market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
      sign_in member

      delete path
      expect(response).to have_http_status(:unprocessable_content)
      expect(Position.exists?(position.id)).to be(true)
    end
  end

  describe "DELETE /groups/:group_id/markets/:market_id/positions/:id (admin)" do
    let(:admin_membership) { create :membership, :admin, group: }
    let(:position) { create :position, market: }
    let(:admin_path) { "/groups/#{group.to_param}/markets/#{market.id}/positions/#{position.id}.json" }

    it "lets an admin cancel another member's position, emailing the owner" do
      ActionMailer::Base.deliveries.clear
      sign_in admin_membership.user
      perform_enqueued_jobs { delete admin_path }

      expect(response).to have_http_status(:no_content)
      expect(Position.exists?(position.id)).to be(false)
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly(position.membership.user.email)
      expect(ActionMailer::Base.deliveries.first.subject).to include(market.title)
    end

    it "forbids non-admin members" do
      sign_in member
      delete admin_path

      expect(response).to have_http_status(:forbidden)
      expect(Position.exists?(position.id)).to be(true)
    end

    it "refuses once the market is locked" do
      position
      market.update_column(:locks_at, 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      sign_in admin_membership.user
      delete admin_path

      expect(response).to have_http_status(:unprocessable_content)
      expect(Position.exists?(position.id)).to be(true)
    end
  end
end
