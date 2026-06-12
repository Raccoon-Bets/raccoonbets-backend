# frozen_string_literal: true

# A Market is a proposition the members of a {Group} trade on ("Will Wenting
# finish her marathon in under 4:30?"). It has two or more {Outcome}s, and members each hold at
# most one {Position} until `locks_at` passes. "Locked" is derived from
# `locks_at` at read time; no job flips a status. After the event, the market's
# oracle resolves it to a winning outcome (Phase 4).
#
# The creator or a group admin may edit `title`, `description`, and `locks_at`
# while the market is open; position holders are emailed about edits that follow
# their positions ({AdminActionMailer}). Outcomes are immutable once any
# position exists.
#
# Associations
# ------------
#
# |                   |                                                              |
# |:------------------|:-------------------------------------------------------------|
# | `group`           | The {Group} the market belongs to.                           |
# | `creator`         | The {Membership} that created the market.                    |
# | `oracle`          | The {Membership} designated to resolve the market.          |
# | `outcomes`        | The {Outcome}s members can trade on, ordered by `position`. |
# | `positions`       | The {Position}s taken on the market.                         |
# | `winning_outcome` | The {Outcome} the market resolved to, if resolved.          |
# | `resolved_by`     | The {Membership} that resolved the market, if resolved.     |
#
# Properties
# ----------
#
# |               |                                                                        |
# |:--------------|:------------------------------------------------------------------------|
# | `title`       | The proposition, phrased as a question.                                |
# | `description` | Optional resolution criteria and context.                              |
# | `locks_at`    | When trading closes. Must be in the future when set.                   |
# | `status`      | `open`, `resolved`, or `voided`.                                       |
# | `resolved_at` | When the market was resolved.                                          |

class Market < ApplicationRecord
  belongs_to :group
  belongs_to :creator, class_name: "Membership", inverse_of: :created_markets
  belongs_to :oracle, class_name: "Membership", inverse_of: :oracle_markets
  belongs_to :winning_outcome, class_name: "Outcome", optional: true, inverse_of: false
  belongs_to :resolved_by, class_name: "Membership", optional: true, inverse_of: false

  # Dependent associations are declared in deletion order: the ledger
  # restriction aborts first if any entries exist (a market with realized money
  # cannot be destroyed directly — only its whole group can), then events and
  # positions are removed before outcomes, which they hold foreign keys to.
  has_many :ledger_entries, dependent: :restrict_with_error
  has_many :market_events, -> { order(:created_at, :id) }, dependent: :delete_all, inverse_of: :market
  has_many :positions, dependent: :destroy
  has_many :outcomes, -> { order(:position) }, dependent: :destroy, inverse_of: :market

  enum :status, {open: "open", resolved: "resolved", voided: "voided"}, validate: true

  validates :title,
            presence: true,
            length:   {maximum: 200}
  validate :at_least_two_outcomes
  validate :outcome_names_unique
  validate :oracle_actively_in_group
  validate :creator_in_group
  validates :locks_at, presence: true
  validate :locks_at_in_future, if: :locks_at_changed?

  # Postponing trading lets the closing-soon notice fire again for the new
  # deadline.
  before_save :clear_closing_soon_notification, if: :locks_at_postponed?

  # @return [true, false] Whether trading has closed because `locks_at` has
  #   passed while the market is still open (awaiting resolution).

  def locked? = open? && locks_at <= Time.current

  # @return [true, false] Whether positions can currently be taken, changed, or
  #   canceled: the market is open and `locks_at` has not passed.

  def open_for_trading? = open? && locks_at.future?

  private

  def at_least_two_outcomes
    errors.add(:outcomes, :too_few) if live_outcomes.size < 2
  end

  def outcome_names_unique
    names = live_outcomes.map(&:name)
    errors.add(:outcomes, :duplicate_names) if names.uniq.size != names.size
  end

  def live_outcomes = outcomes.reject(&:marked_for_destruction?)

  def oracle_actively_in_group
    return unless oracle
    return if oracle.group_id == group_id && oracle.active?

    errors.add(:oracle, :not_a_member)
  end

  def creator_in_group
    return unless creator
    return if creator.group_id == group_id

    errors.add(:creator, :not_a_member)
  end

  def locks_at_in_future
    errors.add(:locks_at, :must_be_future) if locks_at && !locks_at.future?
  end

  def locks_at_postponed?
    will_save_change_to_locks_at? && locks_at_in_database.present? && locks_at.present? &&
      locks_at > locks_at_in_database
  end

  def clear_closing_soon_notification
    self.closing_soon_notified_at = nil
  end
end
