# frozen_string_literal: true

# Full representation of a {Market}: everything in {MarketSerializer} plus the
# description, every position with the holder's name, who resolved it, the
# per-member payout summary, and the resolution audit trail.
#
# Params
# ------
#
# |             |                                                                              |
# |:------------|:--------------------------------------------------------------------------------|
# | `:payouts`  | Per-member net payout rows (`membership_id`, `name`, `net_cents`), if any.  |

class MarketDetailSerializer < MarketSerializer
  attributes :description

  many :positions, resource: PositionSerializer

  attribute :resolved_by do |market|
    market.resolved_by && membership_ref(market.resolved_by)
  end

  attribute :payouts do
    params[:payouts] || []
  end

  attribute :events do |market|
    market.market_events.map do |event|
      {
          action:       event.action,
          actor_name:   event.actor.user.name,
          outcome_name: event.outcome&.name,
          created_at:   event.created_at
      }
    end
  end
end
