# frozen_string_literal: true

module Groups
  # Computes every active member's realized balance for a group with a single
  # grouped SUM over the ledger. Because each market's and each settlement's
  # entries sum to zero, the balances always sum to zero too.

  class BalanceSheet
    # @param group [Group] The group to balance.

    def initialize(group)
      @group = group
    end

    # @return [Hash{Integer => Integer}] Balance in minor units of the
    #   group's currency by membership ID, ordered by membership ID. Every
    #   active membership is included, zero balances and all; negative means
    #   the member owes the group.

    def balances
      sums = group.ledger_entries.group(:membership_id).sum(:amount_cents)
      group.memberships.active.order(:id).pluck(:id).index_with { sums.fetch(it, 0) }
    end

    private

    attr_reader :group
  end
end
