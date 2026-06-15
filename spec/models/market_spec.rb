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

  describe "kind" do
    it "lets an open-ended market omit locks_at and trade until resolved" do
      market = create(:market, :open_ended)
      expect(market).to be_valid
      expect(market.open_for_trading?).to be(true)
      expect(market.locked?).to be(false)
    end

    it "rejects a locks_at on an open-ended market" do
      market = build(:market, :open_ended, locks_at: 1.day.from_now)
      expect(market).not_to be_valid
      expect(market.errors.added?(:locks_at, :not_for_open_ended)).to be(true)
    end

    it "requires locks_at on a scheduled market" do
      market = build(:market, locks_at: nil)
      expect(market).not_to be_valid
      expect(market.errors.added?(:locks_at, :blank)).to be(true)
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

    it "clears closing_soon_notified_at when locks_at is postponed" do
      market = create(:market)
      market.update_column(:closing_soon_notified_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

      market.update!(locks_at: 2.days.from_now)
      expect(market.closing_soon_notified_at).to be_nil
    end

    it "keeps closing_soon_notified_at when locks_at moves earlier" do
      market = create(:market, locks_at: 2.days.from_now)
      market.update_column(:closing_soon_notified_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

      market.update!(locks_at: 1.day.from_now)
      expect(market.closing_soon_notified_at).to be_present
    end
  end
end
