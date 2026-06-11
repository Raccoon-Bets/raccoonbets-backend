# frozen_string_literal: true

require "rails_helper"

RSpec.describe Markets::Resolver do
  let(:group) { create :group }
  let(:market) { create :market, group: }
  let(:yes) { market.outcomes.first }
  let(:no) { market.outcomes.second }
  let(:admin) { create :membership, :admin, group: }

  def lock!(market)
    market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
  end

  describe ".resolve" do
    it "writes win and loss entries that sum to zero and records the resolution" do
      winner1 = create(:position, market:, outcome: yes, amount_cents: 100)
      winner2 = create(:position, market:, outcome: yes, amount_cents: 300)
      loser   = create(:position, market:, outcome: no, amount_cents: 200)
      lock! market

      described_class.resolve market, yes, admin

      expect(market.reload).to be_resolved
      expect(market.winning_outcome).to eq(yes)
      expect(market.resolved_at).to be_present
      expect(market.resolved_by).to eq(admin)

      entries = market.ledger_entries.index_by(&:membership_id)
      expect(entries[winner1.membership_id]).to have_attributes(entry_type: "win", amount_cents: 50, position_id: winner1.id)
      expect(entries[winner2.membership_id]).to have_attributes(entry_type: "win", amount_cents: 150, position_id: winner2.id)
      expect(entries[loser.membership_id]).to have_attributes(entry_type: "loss", amount_cents: -200, position_id: loser.id)
      expect(group).to have_zero_sum_ledger

      expect(market.market_events.sole).to have_attributes(action: "resolved", actor: admin, outcome: yes)
    end

    it "writes no entries when there are no losing positions" do
      create(:position, market:, outcome: yes, amount_cents: 100)
      lock! market

      described_class.resolve market, yes, admin

      expect(market.reload).to be_resolved
      expect(market.ledger_entries).to be_empty
    end

    it "rejects resolving before trading closes" do
      expect { described_class.resolve market, yes, admin }.
          to raise_error(described_class::Error, /before trading closes/)
      expect(market.reload).to be_open
      expect(market.ledger_entries).to be_empty
      expect(market.market_events).to be_empty
    end

    it "rejects resolving an already-resolved market" do
      lock! market
      described_class.resolve market, yes, admin

      expect { described_class.resolve market, no, admin }.
          to raise_error(described_class::Error, /correct it instead/)
    end

    it "rejects resolving a voided market" do
      described_class.void market, admin

      expect { described_class.resolve market.reload, yes, admin }.
          to raise_error(described_class::Error)
    end

    it "rejects an outcome from another market" do
      lock! market
      other = create(:market, group:)

      expect { described_class.resolve market, other.outcomes.first, admin }.
          to raise_error(described_class::Error, /does not belong/)
    end
  end

  describe ".void" do
    it "voids an open market without writing any entries" do
      create(:position, market:, outcome: yes, amount_cents: 100)

      described_class.void market, admin

      expect(market.reload).to be_voided
      expect(market.ledger_entries).to be_empty
      expect(market.market_events.sole).to have_attributes(action: "voided", actor: admin, outcome: nil)
    end

    it "reverses a resolved market's entries, mirroring the originals" do
      create(:position, market:, outcome: yes, amount_cents: 100)
      create(:position, market:, outcome: yes, amount_cents: 200)
      create(:position, market:, outcome: no, amount_cents: 100)
      lock! market
      described_class.resolve market, yes, admin
      originals = market.ledger_entries.to_a

      described_class.void market, admin

      expect(market.reload).to be_voided
      expect(market.winning_outcome).to be_nil
      expect(market.resolved_at).to be_nil
      expect(market.resolved_by).to be_nil
      expect(group).to have_zero_sum_ledger

      reversals = market.ledger_entries.reversal.index_by(&:reverses_entry_id)
      expect(reversals.size).to eq(originals.size)
      originals.each do |original|
        expect(reversals.fetch(original.id)).
            to have_attributes(amount_cents:  -original.amount_cents,
                               membership_id: original.membership_id,
                               position_id:   original.position_id,
                               market_id:     market.id)
      end
      expect(market.ledger_entries.sum(:amount_cents)).to eq(0)
    end

    it "rejects voiding an already-voided market" do
      described_class.void market, admin

      expect { described_class.void market.reload, admin }.to raise_error(described_class::Error)
    end
  end

  describe ".correct" do
    before(:each) do
      create(:position, market:, outcome: yes, amount_cents: 100)
      create(:position, market:, outcome: yes, amount_cents: 200)
      create(:position, market:, outcome: no, amount_cents: 150)
      lock! market
      described_class.resolve market, yes, admin
    end

    it "reverses the original entries and replays the payout for the new outcome" do
      described_class.correct market, no, admin

      expect(market.reload).to be_resolved
      expect(market.winning_outcome).to eq(no)
      expect(market.resolved_by).to eq(admin)
      expect(group).to have_zero_sum_ledger

      # Net effect per member now matches a fresh resolution to `no`.
      expected = Markets::PayoutCalculator.new(positions: market.positions, winning_outcome_id: no.id).payouts
      nets = market.ledger_entries.group(:membership_id).sum(:amount_cents).reject { |_, cents| cents.zero? }
      expect(nets).to eq(expected)

      expect(market.market_events.pluck(:action)).to eq(%w[resolved corrected])
    end

    it "leaves every entry either a reversal or reversed after a subsequent void" do
      described_class.correct market, no, admin
      described_class.void market, admin

      expect(group).to have_zero_sum_ledger
      reversed_ids = market.ledger_entries.reversal.pluck(:reverses_entry_id)
      expect(market.ledger_entries.where.not(entry_type: :reversal).pluck(:id)).to match_array(reversed_ids)
      expect(market.ledger_entries.group(:membership_id).sum(:amount_cents).values).to all(eq(0))
    end

    it "rejects correcting to the outcome already resolved" do
      expect { described_class.correct market, yes, admin }.
          to raise_error(described_class::Error, /already resolved to that outcome/)
    end

    it "rejects correcting an open market" do
      open_market = create(:market, group:)

      expect { described_class.correct open_market, open_market.outcomes.first, admin }.
          to raise_error(described_class::Error, /Only a resolved market/)
    end
  end

  it "rejects a position taken after resolution" do
    create(:position, market:, outcome: yes, amount_cents: 100)
    create(:position, market:, outcome: no, amount_cents: 100)
    lock! market
    described_class.resolve market, yes, admin

    late_position = build(:position, market: market.reload, outcome: no, amount_cents: 100)
    expect(late_position).not_to be_valid
    expect(late_position.errors[:base]).to include("trading is closed for this market")
  end
end
