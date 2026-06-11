# frozen_string_literal: true

require "rails_helper"

RSpec.describe Market do
  describe "outcomes" do
    it "requires at least two" do
      market = build(:market, outcome_names: %w[YES])
      expect(market).not_to be_valid
      expect(market.errors[:outcomes]).to include("must include at least two outcomes")
    end

    it "rejects duplicate names" do
      market = build(:market, outcome_names: %w[YES YES])
      expect(market).not_to be_valid
      expect(market.errors[:outcomes]).to include("must not repeat outcome names")
    end
  end

  describe "oracle" do
    it "must belong to the market's group" do
      market = build(:market, oracle: create(:membership))
      expect(market).not_to be_valid
      expect(market.errors[:oracle]).to include("must be an active member of this group")
    end

    it "must be an active membership" do
      market = build(:market)
      market.oracle = create(:membership, :requested, group: market.group)
      expect(market).not_to be_valid
      expect(market.errors[:oracle]).to include("must be an active member of this group")
    end
  end

  describe "locks_at" do
    it "must be in the future when set" do
      market = build(:market, locks_at: 1.minute.ago)
      expect(market).not_to be_valid
      expect(market.errors[:locks_at]).to include("must be in the future")
    end

    it "can change while no positions exist" do
      market = create(:market)
      expect(market.update(locks_at: 2.days.from_now)).to be(true)
    end

    it "cannot change once a position exists" do
      market = create(:market)
      create(:position, market:)

      market.locks_at = 2.days.from_now
      expect(market).not_to be_valid
      expect(market.errors[:locks_at]).to include("cannot be changed")
    end
  end
end
