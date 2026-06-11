# frozen_string_literal: true

require "rails_helper"

RSpec.describe Position do
  # A whole-second lock time so travel_to (which truncates to whole seconds)
  # can land exactly on it.
  let(:market) { create :market, locks_at: 1.day.from_now.change(usec: 0) }

  describe "lock time" do
    it "accepts positions while locks_at is in the future" do
      travel_to(market.locks_at - 1.second) do
        expect(build(:position, market:)).to be_valid
      end
    end

    it "rejects positions at exactly locks_at" do
      travel_to(market.locks_at) do
        position = build(:position, market:)
        expect(position).not_to be_valid
        expect(position.errors[:base]).to include("trading is closed for this market")
      end
    end

    it "rejects changes to an existing position once locked" do
      position = create(:position, market:)
      market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations

      position.amount_cents += 1
      expect(position).not_to be_valid
      expect(position.errors[:base]).to include("trading is closed for this market")
    end
  end

  describe "amount" do
    it "enforces the group's amount range" do
      group = market.group

      expect(build(:position, market:, amount_cents: group.min_amount_cents)).to be_valid
      expect(build(:position, market:, amount_cents: group.max_amount_cents)).to be_valid

      low = build(:position, market:, amount_cents: group.min_amount_cents - 1)
      expect(low).not_to be_valid
      expect(low.errors[:amount_cents]).to include("must be greater than or equal to #{group.min_amount_cents}")

      high = build(:position, market:, amount_cents: group.max_amount_cents + 1)
      expect(high).not_to be_valid
      expect(high.errors[:amount_cents]).to include("must be less than or equal to #{group.max_amount_cents}")
    end
  end

  describe "coherence" do
    it "requires the outcome to belong to the market" do
      position = build(:position, market:, outcome: create(:market, group: market.group).outcomes.first)
      expect(position).not_to be_valid
      expect(position.errors[:outcome]).to include("must be one of this market’s outcomes")
    end

    it "requires the membership to be active in the market's group" do
      foreign = build(:position, market:, membership: create(:membership))
      expect(foreign).not_to be_valid
      expect(foreign.errors[:membership]).to include("must be an active member of this group")

      requested = build(:position, market:, membership: create(:membership, :requested, group: market.group))
      expect(requested).not_to be_valid
      expect(requested.errors[:membership]).to include("must be an active member of this group")
    end
  end
end
