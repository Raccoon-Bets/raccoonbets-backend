# frozen_string_literal: true

require "rails_helper"

RSpec.describe Groups::BalanceSheet do
  it "nets multi-market, settlement, and reversal history per active member, zero balances included" do
    group     = create(:group)
    alice     = create(:membership, group:)
    bob       = create(:membership, group:)
    carol     = create(:membership, group:)
    bystander = create(:membership, group:)
    create(:membership, :requested, group:) # never included

    # Market 1: Alice (300) beats Bob (100) and Carol (200) → Alice +300.
    market1 = create(:market, group:, creator: alice)
    create(:position, market: market1, outcome: market1.outcomes.first, membership: alice, amount_cents: 300)
    create(:position, market: market1, outcome: market1.outcomes.second, membership: bob, amount_cents: 100)
    create(:position, market: market1, outcome: market1.outcomes.second, membership: carol, amount_cents: 200)
    market1.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
    Markets::Resolver.resolve market1, market1.outcomes.first, alice

    # Market 2: Bob beats Alice for 150, but the market is then voided (reversed).
    market2 = create(:market, group:, creator: bob)
    create(:position, market: market2, outcome: market2.outcomes.first, membership: bob, amount_cents: 150)
    create(:position, market: market2, outcome: market2.outcomes.second, membership: alice, amount_cents: 150)
    market2.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
    Markets::Resolver.resolve market2, market2.outcomes.first, alice
    Markets::Resolver.void market2, alice

    # Bob settles his 100 debt; Carol's settlement gets voided (reversed).
    create(:settlement, group:, payer: bob, payee: alice, amount_cents: 100)
    create(:settlement, group:, payer: carol, payee: alice, amount_cents: 200).void!

    balances = described_class.new(group).balances

    expect(balances).to eq(alice.id     => 200,
                           bob.id       => 0,
                           carol.id     => -200,
                           bystander.id => 0)
    expect(balances.values.sum).to eq(0)
    expect(group).to have_zero_sum_ledger
  end
end
