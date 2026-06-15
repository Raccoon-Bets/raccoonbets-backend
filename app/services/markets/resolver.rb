# frozen_string_literal: true

module Markets
  # Transitions a {Market} through its money-moving state changes — resolve,
  # void, and correct — writing the matching {LedgerEntry} rows and a
  # {MarketEvent} audit record atomically.
  #
  # Every operation runs inside a transaction holding the market's row lock
  # (`market.lock!`), the same lock position placement takes, so a position can never
  # slip in between the payout calculation and the commit.
  #
  # * **resolve** — an open market; writes a `loss` entry (−amount) per losing
  #   position and a `win` entry (+share of the losing pool) per winning
  #   position. Winners' amounts are never ledgered: they were never paid in.
  #   A scheduled market must be past its lock time. Passing `effective_at` (or
  #   resolving an open-ended market) resolves it **early**, settling the pool as
  #   it stood at that instant — positions placed or raised afterward are excluded
  #   (see {PositionChange}), protecting against bets made once the outcome was
  #   known.
  # * **void** — an open market is simply marked voided (nothing was ledgered);
  #   a resolved market additionally has each live entry reversed first.
  # * **correct** — only a resolved market: reverses all live entries, then
  #   replays the calculator for the new outcome.
  #
  # Disallowed transitions raise {Error}, which controllers map to 422.

  class Resolver
    # Raised when a transition is not allowed from the market's current state.
    class Error < StandardError; end

    # One position in the pool being settled: a live {Position}, or a row from
    # the effective-as-of snapshot. `id` orders the calculator's remainder
    # distribution deterministically; `position_id` ties a ledger entry to the
    # live position when one still exists.
    PayoutPosition = Struct.new(:id, :membership_id, :outcome_id, :amount_cents, :position_id)

    class << self
      # Resolves an open market to the given outcome.
      #
      # @param market [Market] The market to resolve.
      # @param outcome [Outcome] The winning outcome.
      # @param actor [Membership] The member resolving (oracle or admin).
      # @param effective_at [Time, nil] When the outcome became known, for an
      #   early resolution; the pool is settled as it stood at this instant.
      #   Defaults to now for open-ended markets; omit for a scheduled market
      #   resolving normally after its lock time.
      # @return [Market] The resolved market.
      # @raise [Error] If the market is not open, a scheduled market is resolved
      #   normally before its lock time, `effective_at` is outside the market's
      #   lifetime, or the outcome is not one of the market's.

      def resolve(market, outcome, actor, effective_at: nil) = new(market).resolve(outcome, actor, effective_at:)

      # Voids a market, reversing its ledger entries if it was resolved.
      #
      # @param market [Market] The market to void.
      # @param actor [Membership] The member voiding (oracle or admin).
      # @return [Market] The voided market.
      # @raise [Error] If the market is already voided.

      def void(market, actor) = new(market).void(actor)

      # Re-resolves a resolved market to a different outcome: reverses the live
      # entries and replays the payout for the new outcome.
      #
      # @param market [Market] The resolved market to correct.
      # @param outcome [Outcome] The corrected winning outcome.
      # @param actor [Membership] The member correcting (admin).
      # @return [Market] The corrected market.
      # @raise [Error] If the market is not resolved, the outcome equals the
      #   current winning outcome, or the outcome is not one of the market's.

      def correct(market, outcome, actor) = new(market).correct(outcome, actor)
    end

    def initialize(market)
      @market = market
    end

    # (see .resolve)
    def resolve(outcome, actor, effective_at: nil)
      locking :market_resolved do
        guard! !market.resolved?, :already_resolved
        guard! market.open?, :not_open
        guard_outcome! outcome

        if early_resolution? effective_at
          market.resolution_effective_at = resolution_cutoff effective_at
        else
          guard! market.locks_at.past?, :not_locked
        end

        write_payout_entries outcome
        market.update! status: :resolved, winning_outcome: outcome,
                       resolved_at: Time.current, resolved_by: actor
        log :resolved, actor, outcome
      end
    end

    # (see .void)
    def void(actor)
      locking :market_voided do
        guard! !market.voided?, :already_voided

        reverse_live_entries if market.resolved?
        market.update! status: :voided, winning_outcome: nil, resolved_at: nil, resolved_by: nil
        log :voided, actor
      end
    end

    # (see .correct)
    def correct(outcome, actor)
      locking :market_corrected do
        guard! market.resolved?, :not_resolved
        guard! outcome.id != market.winning_outcome_id, :same_outcome
        guard_outcome! outcome

        reverse_live_entries
        write_payout_entries outcome
        market.update! winning_outcome: outcome, resolved_at: Time.current, resolved_by: actor
        log :corrected, actor, outcome
      end
    end

    private

    attr_reader :market

    # Runs the transition inside a transaction holding the market's row lock,
    # and registers the realtime broadcast from within it:
    # `ActiveRecord.after_all_transactions_commit` fires the block only after
    # the outermost transaction commits — never on rollback — so subscribers
    # always refetch committed state.
    def locking(event)
      market.transaction do
        market.lock!
        yield
        ActiveRecord.after_all_transactions_commit { broadcast event }
        market
      end
    end

    def broadcast(event)
      GroupChannel.broadcast_event market.group, event, market_id: market.id
      MarketChannel.broadcast_event market, event
      Notifications::DispatchJob.perform_later(
        event: "market_resolved", record_id: market.id, kind: event.to_s.delete_prefix("market_")
      )
    end

    def guard!(condition, error)
      raise Error, I18n.t("markets.resolver.errors.#{error}") unless condition
    end

    def guard_outcome!(outcome)
      guard! outcome.market_id == market.id, :wrong_market
    end

    def write_payout_entries(outcome)
      positions = payout_positions
      payouts = PayoutCalculator.new(positions:, winning_outcome_id: outcome.id).payouts
      positions_by_membership = positions.index_by(&:membership_id)

      payouts.each do |membership_id, amount_cents|
        market.ledger_entries.create! group_id:      market.group_id,
                                      membership_id:,
                                      position_id:   positions_by_membership.fetch(membership_id).position_id,
                                      entry_type:    amount_cents.positive? ? :win : :loss,
                                      amount_cents:
      end
    end

    def payout_positions
      return live_payout_positions unless market.resolution_effective_at

      snapshot_payout_positions market.resolution_effective_at
    end

    def live_payout_positions
      market.positions.map do |position|
        PayoutPosition.new(position.id, position.membership_id, position.outcome_id,
                           position.amount_cents, position.id)
      end
    end

    # Each membership's holding as of the cutoff: its latest {PositionChange} at
    # or before that instant, dropping those that had cancelled by then. The
    # change row's id orders the calculator's remainder distribution
    # deterministically; `position_id` ties the ledger entry to the live
    # position when one still exists.
    def snapshot_payout_positions(effective_at)
      live_position_ids = market.positions.pluck(:membership_id, :id).to_h

      latest_changes_as_of(effective_at).filter_map do |change|
        next if change.amount_cents.nil?

        PayoutPosition.new(change.id, change.membership_id, change.outcome_id,
                           change.amount_cents, live_position_ids[change.membership_id])
      end
    end

    def latest_changes_as_of(effective_at)
      PositionChange.
          where(market_id: market.id, created_at: ..effective_at).
          order(membership_id: :asc, created_at: :desc, id: :desc).
          select("DISTINCT ON (membership_id) *")
    end

    def early_resolution?(effective_at) = effective_at.present? || market.open_ended?

    def resolution_cutoff(effective_at)
      effective_at ||= Time.current
      guard! effective_at.between?(market.created_at, Time.current), :effective_at_invalid
      effective_at
    end

    # Reverses every entry that is still in effect: not a reversal itself and
    # not already reversed. After a correct, only the replayed batch is live,
    # so a later void undoes exactly that batch.
    def reverse_live_entries
      live_entries.each do |entry|
        market.ledger_entries.create! group_id:       entry.group_id,
                                      membership_id:  entry.membership_id,
                                      position_id:    entry.position_id,
                                      entry_type:     :reversal,
                                      amount_cents:   -entry.amount_cents,
                                      reverses_entry: entry
      end
    end

    def live_entries
      reversed_ids = market.ledger_entries.reversal.pluck(:reverses_entry_id)
      market.ledger_entries.where.not(entry_type: :reversal).where.not(id: reversed_ids)
    end

    def log(action, actor, outcome=nil)
      market.market_events.create! action:, actor:, outcome:
    end
  end
end
