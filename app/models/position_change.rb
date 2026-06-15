# frozen_string_literal: true

# A PositionChange is an append-only record of one committed change to a
# member's {Position} on a {Market}: the {Outcome} backed and the amount held
# after the change — or both null to record a cancellation, meaning the member
# holds no position from that point on.
#
# The history lets a market be resolved against an effective-as-of cutoff (see
# {Markets::Resolver}): each member's holding can be reconstructed as of any
# instant, so bets placed or raised after the outcome became known are excluded
# from the payout. Rows are written automatically by {Position} on save and on
# cancellation, and are read-only once persisted.
#
# Associations
# ------------
#
# |              |                                        |
# |:-------------|:----------------------------------------|
# | `market`     | The {Market} traded on.                |
# | `membership` | The {Membership} whose holding moved.  |
# | `outcome`    | The {Outcome} backed after the change; null for a cancellation. |
#
# Properties
# ----------
#
# |                |                                                                       |
# |:---------------|:-----------------------------------------------------------------------|
# | `amount_cents` | The amount held after the change, in minor units; null for a cancellation. |
# | `created_at`   | When the change committed — the timestamp an effective-as-of cutoff compares against. |

class PositionChange < ApplicationRecord
  belongs_to :market
  belongs_to :membership
  belongs_to :outcome, optional: true

  # A cancellation records neither outcome nor amount; otherwise both are set.
  validates :amount_cents,
            numericality: {only_integer: true, greater_than: 0},
            allow_nil:    true

  # Every persisted row is read-only: the history is append-only.
  #
  # @return [true, false] Whether the row can no longer be written.

  def readonly? = persisted?
end
