# frozen_string_literal: true

# Asserts the core ledger invariant: a group's ledger entries always sum to
# zero. Use after any spec action that writes ledger entries (resolution,
# void, correction, settlements).
RSpec::Matchers.define :have_zero_sum_ledger do
  match { |group| group.ledger_entries.sum(:amount_cents).zero? }

  failure_message do |group|
    "expected the group ledger to sum to 0, got #{group.ledger_entries.sum(:amount_cents)} " \
      "across #{group.ledger_entries.count} entries"
  end
end
