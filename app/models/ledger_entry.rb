# frozen_string_literal: true

# A LedgerEntry records one realized movement of money for one {Membership}.
# Amounts are NOT ledgered when a {Position} is taken; entries are written only
# when money actually changes hands — at resolution (wins and losses), when a
# {Settlement} is recorded, and when either is reversed.
#
# The ledger is **append-only**: {#readonly?} is true for every persisted
# entry, so rows can never be updated or destroyed individually. Mistakes are
# undone by appending a `reversal` entry (negated amount, `reverses_entry`
# pointing at the original); each entry can be reversed at most once (unique
# index). Group deletion removes entries in bulk via the {Group} association's
# `dependent: :delete_all`, which bypasses instantiation and therefore the
# read-only guard.
#
# Invariant: the entries of each market and each settlement sum to zero, so
# every group's ledger always sums to zero. A membership's balance is simply
# the sum of its entries (negative = owes the group).
#
# Associations
# ------------
#
# |                  |                                                            |
# |:-----------------|:------------------------------------------------------------|
# | `group`          | The {Group} (denormalized from the market or settlement).  |
# | `membership`     | The {Membership} whose balance this entry moves.           |
# | `market`         | The {Market} that produced this entry, if any.             |
# | `position`       | The {Position} that produced this entry, if any.           |
# | `settlement`     | The {Settlement} that produced this entry, if any.         |
# | `reverses_entry` | The LedgerEntry this `reversal` entry undoes, if any.      |
#
# Properties
# ----------
#
# |                |                                                                                       |
# |:---------------|:----------------------------------------------------------------------------------------|
# | `amount_cents` | The signed movement in minor units of the group's currency; never zero.              |
# | `entry_type`   | `win`, `loss`, `reversal`, `settlement_payment`, or `settlement_receipt`.            |

class LedgerEntry < ApplicationRecord
  belongs_to :group
  belongs_to :membership
  belongs_to :market, optional: true
  belongs_to :position, optional: true
  belongs_to :settlement, optional: true
  belongs_to :reverses_entry, class_name: "LedgerEntry", optional: true, inverse_of: false

  enum :entry_type,
       {
           win:                "win",
           loss:               "loss",
           reversal:           "reversal",
           settlement_payment: "settlement_payment",
           settlement_receipt: "settlement_receipt"
       },
       validate: true

  validates :amount_cents,
            presence:     true,
            numericality: {only_integer: true, other_than: 0}
  validates :reverses_entry_id, uniqueness: true, allow_nil: true
  validates :reverses_entry, presence: {if: :reversal?}, absence: {unless: :reversal?}

  # Every persisted entry is read-only: the ledger is append-only.
  #
  # @return [true, false] Whether the entry can no longer be written.

  def readonly? = persisted?
end
