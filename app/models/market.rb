# frozen_string_literal: true

# A Market is a proposition the members of a {Group} trade on ("Will Wenting
# finish her marathon in under 4:30?"). It has two or more {Outcome}s, and members each hold at
# most one {Position} while it is {#open_for_trading?}. A `scheduled` market closes
# trading when `locks_at` passes ("locked" is derived from `locks_at` at read time;
# no job flips a status); an `open_ended` market has no `locks_at` and trades until
# it is resolved. After the event, the market's oracle resolves it to a winning
# outcome — early, against an effective-as-of cutoff, for open-ended or
# time-sensitive markets (see {Markets::Resolver}).
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
# | `comments`        | The members' {Comment}s on the market, oldest first.        |
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
# | `kind`        | `scheduled` (closes at `locks_at`) or `open_ended` (trades until resolved). |
# | `locks_at`    | When trading closes; required for `scheduled`, null for `open_ended`.   |
# | `status`      | `open`, `resolved`, or `voided`.                                       |
# | `resolved_at` | When the market was resolved.                                          |
# | `resolution_effective_at` | The cutoff a resolution settled as of, when resolved early. |

class Market < ApplicationRecord
  # How far before `locks_at` the "closing soon" notice fires.
  CLOSING_SOON_WINDOW = 60.minutes

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
  has_many :comments, -> { order(:created_at, :id) }, dependent: :delete_all, inverse_of: :market
  has_many :positions, dependent: :destroy
  # Deleted before outcomes, which the change rows hold a foreign key to.
  has_many :position_changes, dependent: :delete_all
  has_many :outcomes, -> { order(:position) }, dependent: :destroy, inverse_of: :market

  enum :status, {open: "open", resolved: "resolved", voided: "voided"}, validate: true
  enum :kind, {scheduled: "scheduled", open_ended: "open_ended"}, validate: true

  validates :title,
            presence: true,
            length:   {maximum: 200}
  validate :at_least_two_outcomes
  validate :outcome_names_unique
  validate :oracle_actively_in_group
  validate :creator_in_group
  validates :locks_at, presence: true, if: :scheduled?
  validate :open_ended_has_no_locks_at, if: :open_ended?
  validate :locks_at_in_future, if: :locks_at_changed?

  # Postponing trading lets the closing-soon notice fire again for the new
  # deadline.
  before_save :clear_closing_soon_notification, if: :locks_at_postponed?

  # Schedule the closing-soon notice for its exact moment whenever the lock time
  # is set or changed. {Notifications::ClosingSoonSweepJob} is the safety net if
  # a scheduled job is ever lost.
  after_commit :schedule_closing_soon_notification, if: :saved_change_to_locks_at?

  # @return [true, false] Whether a scheduled market's trading has closed
  #   because `locks_at` has passed while it is still open (awaiting
  #   resolution). Open-ended markets are never time-locked.

  def locked? = scheduled? && open? && locks_at <= Time.current

  # @return [true, false] Whether trading is still open but `locks_at` falls
  #   within the {CLOSING_SOON_WINDOW} ahead — the moment the closing-soon
  #   notice becomes due. Open-ended markets never close soon.

  def closing_soon? = scheduled? && open? && locks_at&.future? && locks_at <= CLOSING_SOON_WINDOW.from_now

  # @return [true, false] Whether positions can currently be taken, changed, or
  #   canceled: the market is open, and (for scheduled markets) `locks_at` has
  #   not passed. Open-ended markets trade until they are resolved.

  def open_for_trading? = open? && (open_ended? || locks_at.future?)

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

  def open_ended_has_no_locks_at
    errors.add(:locks_at, :not_for_open_ended) if locks_at.present?
  end

  def locks_at_postponed?
    will_save_change_to_locks_at? && locks_at_in_database.present? && locks_at.present? &&
      locks_at > locks_at_in_database
  end

  def clear_closing_soon_notification
    self.closing_soon_notified_at = nil
  end

  def schedule_closing_soon_notification
    return unless scheduled? && open? && locks_at&.future?

    Notifications::ClosingSoonNotifyJob.set(wait_until: locks_at - CLOSING_SOON_WINDOW).perform_later(id)
  end
end
