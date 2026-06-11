# frozen_string_literal: true

# Action Cable channel for a single {Market}: live pool totals as positions
# land and the market's resolution events. The market detail and resolve views
# subscribe and reload the market on any event.
#
# Parameters
# ----------
#
# |      |                       |
# |:-----|:----------------------|
# | `id` | The ID of a Market.   |
#
# Only active members of the market's (active) group may subscribe.
#
# Events
# ------
#
# * `position_changed` — `{type:, market_id:, pools:, total_pool_cents:, position_count:}`
#   where `pools` maps outcome IDs to `{pool_cents:, position_count:}`
#   ({Position.pool_by_outcome}).
# * `market_resolved`, `market_voided`, `market_corrected` — `{type:}`.

class MarketChannel < ApplicationCable::Channel

  # @private
  def subscribed
    market = Market.joins(:group).merge(Group.active).find_by(id: params[:id])
    group  = market&.group
    return reject unless group&.memberships&.exists?(user: current_user, status: :active)

    stream_for market
  end

  class << self
    # Broadcasts the market's refreshed per-outcome pools after a position is
    # placed, changed, or canceled.
    #
    # @param market [Market] The market whose pools changed.

    def broadcast_position_changed(market)
      pools = Position.pool_by_outcome([market])
      broadcast_to market, {
          type:             :position_changed,
          market_id:        market.id,
          pools:,
          total_pool_cents: pools.values.sum { it[:pool_cents] },
          position_count:   pools.values.sum { it[:position_count] }
      }
    end

    # Broadcasts an event to the market's subscribers.
    #
    # @param market [Market] The market whose subscribers to notify.
    # @param type [Symbol, String] The event type (see class docs).

    def broadcast_event(market, type)
      broadcast_to market, {type:}
    end
  end
end
