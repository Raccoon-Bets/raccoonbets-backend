# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::TransferSuggester do
  def settle(balances)
    described_class.new(balances).transfers.each do |transfer|
      balances[transfer.payer_membership_id] += transfer.amount_cents
      balances[transfer.payee_membership_id] -= transfer.amount_cents
    end
    balances
  end

  it "suggests transfers that zero every balance with at most n−1 transfers" do
    balances = {1 => -300, 2 => 100, 3 => 250, 4 => -50, 5 => 0}

    transfers = described_class.new(balances).transfers

    expect(transfers.size).to be <= 4
    expect(settle(balances).values).to all(eq(0))
  end

  it "returns no transfers when everyone is settled" do
    expect(described_class.new({1 => 0, 2 => 0}).transfers).to be_empty
  end

  it "matches the largest debtor with the largest creditor, ties by membership id ascending" do
    transfers = described_class.new({4 => -100, 2 => -100, 3 => 200}).transfers

    expect(transfers.map(&:to_h)).to eq([
        {payer_membership_id: 2, payee_membership_id: 3, amount_cents: 100},
        {payer_membership_id: 4, payee_membership_id: 3, amount_cents: 100}
    ])
  end

  it "zeroes randomized balances within n−1 transfers (randomized)" do
    random = Random.new(2026_06_09)

    50.times do
      count    = random.rand(2..10)
      amounts  = (1...count).map { random.rand(-5000..5000) }
      balances = (1..count).zip(amounts + [-amounts.sum]).to_h

      transfers = described_class.new(balances).transfers

      expect(transfers.size).to be <= count - 1
      expect(transfers.map(&:amount_cents)).to all(be_positive)
      expect(settle(balances).values).to all(eq(0))
    end
  end

  it "suggests the remaining transfers after a partial settlement is recorded" do
    group = create(:group)
    alice = create(:membership, group:)
    bob   = create(:membership, group:)
    market = create(:market, group:)
    create(:position, market:, outcome: market.outcomes.first, membership: alice, amount_cents: 500)
    create(:position, market:, outcome: market.outcomes.second, membership: bob, amount_cents: 500)
    market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
    Markets::Resolver.resolve market, market.outcomes.first, alice

    create(:settlement, group:, payer: bob, payee: alice, amount_cents: 200)

    transfers = described_class.new(Groups::BalanceSheet.new(group).balances).transfers
    expect(transfers.map(&:to_h)).to eq([
        {payer_membership_id: bob.id, payee_membership_id: alice.id, amount_cents: 300}
    ])
  end
end
