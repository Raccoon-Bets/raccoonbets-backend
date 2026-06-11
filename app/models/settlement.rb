# frozen_string_literal: true

# A Settlement records that one member paid another out-of-band (Venmo, cash,
# …) to settle part or all of a ledger balance. Creating a Settlement also
# appends its two {LedgerEntry} rows in the same transaction: a
# `settlement_payment` of +amount to the payer (moving their negative balance
# toward zero) and a `settlement_receipt` of −amount to the payee, so the pair
# always sums to zero.
#
# Settlements are never deleted: {#void!} appends reversal entries and stamps
# `voided_at`.
#
# Associations
# ------------
#
# |                  |                                                  |
# |:-----------------|:--------------------------------------------------|
# | `group`          | The {Group} the settlement happened in.          |
# | `payer`          | The {Membership} that paid.                      |
# | `payee`          | The {Membership} that was paid.                  |
# | `recorded_by`    | The {Membership} that recorded the settlement.   |
# | `ledger_entries` | The entries the settlement appended.             |
#
# Properties
# ----------
#
# |                  |                                                                       |
# |:-----------------|:------------------------------------------------------------------------|
# | `amount_cents`   | The amount paid, in minor units of the group's currency; positive.   |
# | `payment_method` | `venmo`, `paypal`, `cashapp`, `cash`, or `other`.                     |
# | `note`           | Optional free-text note.                                              |
# | `voided_at`      | When the settlement was voided, if it was.                            |

class Settlement < ApplicationRecord
  belongs_to :group
  belongs_to :payer, class_name: "Membership", foreign_key: :payer_membership_id,
                      inverse_of: :settlements_as_payer
  belongs_to :payee, class_name: "Membership", foreign_key: :payee_membership_id,
                      inverse_of: :settlements_as_payee
  belongs_to :recorded_by, class_name: "Membership", inverse_of: :recorded_settlements

  has_many :ledger_entries, dependent: :restrict_with_error

  enum :payment_method,
       {venmo: "venmo", paypal: "paypal", cashapp: "cashapp", cash: "cash", other: "other"},
       validate: true

  validates :amount_cents,
            presence:     true,
            numericality: {only_integer: true, greater_than: 0}
  validates :note, length: {maximum: 500}, allow_nil: true
  validate :payee_distinct_from_payer
  validate :parties_actively_in_group

  after_create :write_ledger_entries

  # @return [true, false] Whether the settlement has been voided.

  def voided? = voided_at.present?

  # Voids the settlement: appends a reversal {LedgerEntry} for each of its
  # original entries and stamps `voided_at`. Idempotent and race-safe (the
  # settlement row is locked); voiding an already-voided settlement is a
  # no-op.
  #
  # @return [Settlement] The settlement.

  def void!
    with_lock do
      next if voided?

      ledger_entries.where.not(entry_type: :reversal).find_each { write_reversal it }
      update! voided_at: Time.current
    end
    self
  end

  private

  def write_ledger_entries
    ledger_entries.create! group:, membership: payer, entry_type: :settlement_payment,
                           amount_cents: amount_cents
    ledger_entries.create! group:, membership: payee, entry_type: :settlement_receipt,
                           amount_cents: -amount_cents
  end

  def write_reversal(entry)
    ledger_entries.create! group:, membership_id: entry.membership_id, entry_type: :reversal,
                           amount_cents: -entry.amount_cents, reverses_entry: entry
  end

  def payee_distinct_from_payer
    return unless payer_membership_id && payer_membership_id == payee_membership_id

    errors.add(:payee, :same_as_payer)
  end

  def parties_actively_in_group
    %i[payer payee recorded_by].each do |party|
      membership = public_send(party)
      next if membership.nil? || (membership.group_id == group_id && membership.active?)

      errors.add(party, :not_a_member)
    end
  end
end
