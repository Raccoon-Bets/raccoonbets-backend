# frozen_string_literal: true

# Loads the instance variables {MarketSerializer} and {MarketDetailSerializer}
# read beyond the markets themselves. Include in controllers that render market
# JSON (alongside {GroupScoping}, which provides `current_group` and
# `current_membership`).

module Groups::TradingContext
  private

  # Loads per-outcome pool totals, the viewing member's positions, and the
  # group currency for the given markets.
  def load_trading_context(markets)
    @pools         = Position.pool_by_outcome(markets)
    @my_positions  = current_membership.positions.where(market: markets).index_by(&:market_id)
    @currency      = current_group.currency
  end

  # Loads the per-member net payout summary for a single market's detail view:
  # the sum of the market's ledger entries per membership, zero rows omitted,
  # largest winners first.
  def load_resolution_context(market)
    nets  = market.ledger_entries.group(:membership_id).sum(:amount_cents).reject { |_, cents| cents.zero? }
    names = current_group.memberships.where(id: nets.keys).joins(:user).pluck(:id, "users.name").to_h

    @payouts = nets.
        sort_by { |membership_id, cents| [-cents, membership_id] }.
        map { |membership_id, cents| {membership_id:, name: names[membership_id], net_cents: cents} }
  end
end
