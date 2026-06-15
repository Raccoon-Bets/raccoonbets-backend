# frozen_string_literal: true

# A Position is a member's single holding on a {Market}: an {Outcome} and an
# amount in minor units of the group's currency. Each member holds at most one
# position per market (enforced by a unique index); changing outcome or amount
# is an update of the same row, and canceling destroys it — all only while the
# market is {Market#open_for_trading?}.
#
# The market's oracle may take a position like anyone else.
#
# Associations
# ------------
#
# |              |                                        |
# |:-------------|:----------------------------------------|
# | `market`     | The {Market} being traded on.          |
# | `outcome`    | The {Outcome} backed.                  |
# | `membership` | The {Membership} holding the position. |
#
# Properties
# ----------
#
# |                |                                                                        |
# |:---------------|:------------------------------------------------------------------------|
# | `amount_cents` | The amount, in minor units; within the group's min/max amount limits. |

class Position < ApplicationRecord
  belongs_to :market
  belongs_to :outcome
  belongs_to :membership

  # A position that has been resolved into the ledger can no longer be destroyed
  # directly; group deletion removes the entries first.
  has_many :ledger_entries, dependent: :restrict_with_error

  # Append-only history (in the same transaction as the position) so a market
  # can be resolved against an effective-as-of cutoff. Skipped on cascade
  # deletes, which take the whole market's history with them.
  after_destroy :record_cancellation, unless: :destroyed_by_association
  after_save :record_change, unless: :destroyed_by_association

  # Realtime: any committed position change moves the market's pools. Skipped
  # when the positions are only disappearing as part of a market/group cascade
  # delete.
  after_commit :broadcast_change, unless: :destroyed_by_association

  validates :amount_cents,
            presence:     true,
            numericality: {only_integer: true, greater_than: 0}
  validates :membership_id, uniqueness: {scope: :market_id}
  validate :outcome_belongs_to_market
  validate :membership_actively_in_group
  validate :market_open_for_trading
  validate :amount_within_group_limits

  # Sums the amounts riding on each outcome of the given markets.
  #
  # @param markets [Enumerable<Market>, ActiveRecord::Relation] The markets to total.
  # @return [Hash{Integer => Hash}] A map from outcome ID to
  #   `{pool_cents:, position_count:}`. Outcomes with no positions are absent.

  def self.pool_by_outcome(markets)
    where(market: markets).
        group(:outcome_id).
        pluck(:outcome_id, Arel.sql("SUM(amount_cents)"), Arel.sql("COUNT(*)")).
        to_h { |outcome_id, sum, count| [outcome_id, {pool_cents: sum, position_count: count}] }
  end

  private

  def broadcast_change
    MarketChannel.broadcast_position_changed market
    GroupChannel.broadcast_event market.group, :market_updated, market_id: market_id
  end

  def record_change
    return unless saved_change_to_outcome_id? || saved_change_to_amount_cents?

    PositionChange.create! market_id:, membership_id:, outcome_id:, amount_cents:
  end

  def record_cancellation
    PositionChange.create! market_id:, membership_id:
  end

  def outcome_belongs_to_market
    return unless outcome
    return if outcome.market_id == market_id

    errors.add(:outcome, :wrong_market)
  end

  def membership_actively_in_group
    return unless membership && market
    return if membership.group_id == market.group_id && membership.active?

    errors.add(:membership, :not_a_member)
  end

  def market_open_for_trading
    return unless market
    return if market.open_for_trading?

    errors.add(:base, :trading_closed)
  end

  def amount_within_group_limits
    return unless market && amount_cents

    group = market.group
    errors.add(:amount_cents, :greater_than_or_equal_to, count: group.min_amount_cents) if amount_cents < group.min_amount_cents
    errors.add(:amount_cents, :less_than_or_equal_to, count: group.max_amount_cents) if amount_cents > group.max_amount_cents
  end
end
