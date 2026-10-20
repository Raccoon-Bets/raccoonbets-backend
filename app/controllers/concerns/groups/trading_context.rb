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
    context = Groups::MemberQueries.new(current_membership).trading_context(markets)
    @pools, @my_positions, @currency = context.values_at(:pools, :my_positions, :currency)
  end

  # Loads the per-member net payout summary for a single market's detail view:
  # the sum of the market's ledger entries per membership, zero rows omitted,
  # largest winners first.
  def load_resolution_context(market)
    @payouts = Groups::MemberQueries.new(current_membership).payouts(market)
  end

  # Loads a market with everything its detail view renders, along with that
  # view's trading and resolution context.
  def load_market_detail(id)
    market = Groups::MemberQueries.new(current_membership).market(id)
    load_trading_context [market]
    load_resolution_context market
    market
  end

  # Re-renders the same payload as `GET /markets/:id` for `@market`, so the
  # store can replace its loaded market (comments, pools, and positions all
  # consistent).
  def render_market_detail
    @market = load_market_detail(@market.id)
    render "groups/markets/show"
  end
end
