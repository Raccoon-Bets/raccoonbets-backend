# frozen_string_literal: true

module Groups
  # Suggests the transfers that settle a group's balances: repeatedly matches
  # the largest debtor with the largest creditor (ties broken by membership ID
  # ascending, so suggestions are deterministic) for the smaller of the two
  # amounts. Each transfer zeroes at least one party, so at most n−1 transfers
  # zero all n balances.

  class TransferSuggester
    # One suggested payment from a debtor to a creditor.
    Transfer = Data.define(:payer_membership_id, :payee_membership_id, :amount_cents)

    # @param balances [Hash{Integer => Integer}] Balance in minor units by
    #   membership ID, as produced by {BalanceSheet#balances}; must sum to
    #   zero.

    def initialize(balances)
      @balances = balances
    end

    # @return [Array<Transfer>] The transfers that bring every balance to
    #   exactly zero.

    def transfers
      debtors   = @balances.filter_map { |id, cents| [id, -cents] if cents.negative? }
      creditors = @balances.filter_map { |id, cents| [id, cents] if cents.positive? }
      suggestions = []

      until debtors.empty? || creditors.empty?
        debtor   = largest(debtors)
        creditor = largest(creditors)
        amount   = [debtor[1], creditor[1]].min

        suggestions << Transfer.new(payer_membership_id: debtor[0],
                                    payee_membership_id: creditor[0],
                                    amount_cents:        amount)
        debtor[1] -= amount
        creditor[1] -= amount
        debtors.delete(debtor) if debtor[1].zero?
        creditors.delete(creditor) if creditor[1].zero?
      end

      suggestions
    end

    private

    def largest(parties) = parties.min_by { |id, cents| [-cents, id] }
  end
end
