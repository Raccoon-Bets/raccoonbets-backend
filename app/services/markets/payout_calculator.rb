# frozen_string_literal: true

module Markets
  # Computes the parimutuel payout for a market's positions given the winning
  # outcome: winners split the losing pool pro-rata by amount (and keep their
  # own amounts, which were never ledgered); losers lose their amounts.
  #
  # Pure integer math: exact shares are Rationals, rounded down to whole minor
  # units, with the leftover cents distributed by largest remainder — ties
  # broken by position ID ascending, so the result is deterministic. The returned
  # amounts always sum to zero.
  #
  # Degenerate cases — no positions, no winning positions, or no losing positions — produce
  # an empty result: no money moves.

  class PayoutCalculator
    # @param positions [Enumerable<#id, #membership_id, #outcome_id, #amount_cents>]
    #   The market's positions (at most one per membership).
    # @param winning_outcome_id [Integer] The ID of the winning outcome.

    def initialize(positions:, winning_outcome_id:)
      @positions          = positions.to_a
      @winning_outcome_id = winning_outcome_id
    end

    # @return [Hash{Integer => Integer}] Signed minor-unit amounts by
    #   membership ID: each loser's amount negated, each winner's share of the
    #   losing pool. Zero shares are omitted; the values sum to zero.

    def payouts
      return {} if winners.empty? || losers.empty?

      losses.merge(winnings).reject { |_, cents| cents.zero? }
    end

    private

    attr_reader :positions, :winning_outcome_id

    def winners = @winners ||= positions.select { it.outcome_id == winning_outcome_id }
    def losers = @losers ||= positions.reject { it.outcome_id == winning_outcome_id }
    def losing_pool = @losing_pool ||= losers.sum(&:amount_cents)
    def winning_pool = @winning_pool ||= winners.sum(&:amount_cents)

    def losses = losers.to_h { [it.membership_id, -it.amount_cents] }

    def winnings
      shares = winners.index_with { exact_share(it).floor }
      distribute_remainder shares
      shares.to_h { |position, cents| [position.membership_id, cents] }
    end

    def exact_share(position) = Rational(losing_pool * position.amount_cents, winning_pool)

    # Hands the cents lost to flooring, one each, to the positions with the largest
    # fractional remainders; ties go to the lower position ID.
    def distribute_remainder(shares)
      remainder = losing_pool - shares.values.sum
      winners.
          sort_by { |position| [shares[position] - exact_share(position), position.id] }.
          first(remainder).
          each { shares[it] += 1 }
    end
  end
end
