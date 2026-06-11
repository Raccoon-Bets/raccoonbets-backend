# frozen_string_literal: true

require "rails_helper"

# Outcome 1 is the winning outcome throughout; outcome 2 loses.
RSpec.describe Markets::PayoutCalculator do
  def position(id, membership, outcome, amount)
    Struct.new(:id, :membership_id, :outcome_id, :amount_cents).new(id, membership, outcome, amount)
  end

  def winning_position(id, membership, amount) = position(id, membership, 1, amount)
  def losing_position(id, membership, amount) = position(id, membership, 2, amount)

  def payouts_for(positions)
    described_class.new(positions:, winning_outcome_id: 1).payouts
  end

  it "splits the losing pool pro-rata when amounts divide evenly" do
    positions = [
        winning_position(1, 10, 100),
        winning_position(2, 11, 300),
        losing_position(3, 12, 250),
        losing_position(4, 13, 150)
    ]

    expect(payouts_for(positions)).to eq(10 => 100, 11 => 300, 12 => -250, 13 => -150)
  end

  it "rounds an indivisible pool by largest remainder, breaking ties by position id ascending" do
    positions = [
        winning_position(7, 10, 100),
        winning_position(5, 11, 100),
        winning_position(9, 12, 100),
        losing_position(1, 13, 100)
    ]

    # Each winner's exact share is 33⅓: floors sum to 99, so the one leftover
    # cent goes — remainders being equal — to the lowest position id (5).
    expect(payouts_for(positions)).to eq(11 => 34, 10 => 33, 12 => 33, 13 => -100)
  end

  it "gives remainder cents to the largest fractional remainders first" do
    positions = [
        winning_position(1, 10, 200), # exact share 66.67
        winning_position(2, 11, 100), # exact share 33.33
        losing_position(3, 12, 100)
    ]

    expect(payouts_for(positions)).to eq(10 => 67, 11 => 33, 12 => -100)
  end

  it "is deterministic regardless of input order" do
    positions = [
        winning_position(3, 10, 17),
        winning_position(1, 11, 29),
        winning_position(2, 12, 54),
        losing_position(4, 13, 101)
    ]

    expect(payouts_for(positions)).to eq(payouts_for(positions.reverse))
    expect(payouts_for(positions)).to eq(payouts_for(positions.shuffle(random: Random.new(42))))
  end

  it "omits winners whose share rounds to zero" do
    positions = [
        winning_position(1, 10, 100),
        winning_position(2, 11, 100),
        winning_position(3, 12, 100),
        losing_position(4, 13, 2)
    ]

    payouts = payouts_for(positions)
    expect(payouts).to eq(10 => 1, 11 => 1, 13 => -2)
    expect(payouts.values).to all(be_nonzero)
  end

  it "returns an empty result with no positions" do
    expect(payouts_for([])).to eq({})
  end

  it "returns an empty result when nobody held the winning outcome" do
    expect(payouts_for([losing_position(1, 10, 100), losing_position(2, 11, 200)])).to eq({})
  end

  it "returns an empty result when everybody held the winning outcome" do
    expect(payouts_for([winning_position(1, 10, 100), winning_position(2, 11, 200)])).to eq({})
  end

  it "returns an empty result for a single holder" do
    expect(payouts_for([winning_position(1, 10, 100)])).to eq({})
    expect(payouts_for([losing_position(1, 10, 100)])).to eq({})
  end

  it "always sums to zero, pays winners, and charges losers their exact amounts (randomized)" do
    random = Random.new(2026_06_09)

    100.times do
      positions = (1..random.rand(2..8)).map do |i|
        position(i, 100 + i, random.rand(1..3), random.rand(1..5000))
      end
      winning_outcome_id = random.rand(1..3)

      payouts = described_class.new(positions:, winning_outcome_id:).payouts
      winners, losers = positions.partition { it.outcome_id == winning_outcome_id }

      expect(payouts.values.sum).to eq(0)
      expect(payouts.values).to all(be_nonzero)
      next if payouts.empty?

      losers.each { expect(payouts.fetch(it.membership_id)).to eq(-it.amount_cents) }
      winners.each { expect(payouts.fetch(it.membership_id, 0)).to be >= 0 }
      expect(payouts.values.select(&:positive?).sum).to eq(losers.sum(&:amount_cents))
    end
  end
end
