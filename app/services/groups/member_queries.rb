# frozen_string_literal: true

# The market and financial data a member can see in their {Group}, shared by
# the website API and the assistant tools ({Mcp::ToolContext}) so both return
# the same markets, pools, and balances.

class Groups::MemberQueries
  # @param membership [Membership] The viewing member, whose own positions
  #   appear in the results.

  def initialize(membership)
    @membership = membership
    @group = membership.group
  end

  # @param status [String, nil] Optional filter: `open`, `resolved`, `voided`,
  #   or `locked` (open but past `locks_at`).
  # @return [ActiveRecord::Relation<Market>] The group's markets in feed order:
  #   open markets first by soonest `locks_at`, then resolved and voided
  #   markets, most recently concluded first.

  def markets(status: nil)
    scope = @group.markets.includes(:outcomes, creator: :user, oracle: :user)
    scope = case status
              when "locked" then scope.open.where(locks_at: ..Time.current)
              when "open", "resolved", "voided" then scope.where(status:)
              else scope
            end
    scope.order(Arel.sql(<<~SQL.squish))
      CASE WHEN status = 'open' THEN 0 ELSE 1 END,
      CASE WHEN status = 'open' THEN locks_at END ASC,
      COALESCE(resolved_at, locks_at) DESC,
      id ASC
    SQL
  end

  # @param id [Integer] The market's ID within the group.
  # @return [Market] The market, with every association {MarketDetailSerializer}
  #   renders preloaded.
  # @raise [ActiveRecord::RecordNotFound] If the group has no such market.

  def market(id)
    @group.markets.includes(:outcomes, positions: {membership: :user}, creator: :user, oracle: :user,
                            resolved_by: :user, market_events: [:outcome, {actor: :user}],
                            comments: {author: :user}).find(id)
  end

  # @param markets [Enumerable<Market>] The markets being rendered.
  # @return [Hash] The {MarketSerializer} params for the markets: per-outcome
  #   pool totals (`pools`), the viewer's positions by market ID
  #   (`my_positions`), and the group's `currency`.

  def trading_context(markets)
    {pools: Position.pool_by_outcome(markets),
     my_positions: @membership.positions.where(market: markets).index_by(&:market_id), currency: @group.currency}
  end

  # @param market [Market] A market in the group.
  # @return [Array<Hash>] Each member's realized net payout from the market
  #   (`membership_id`, `name`, `net_cents`), largest winners first, with
  #   zero nets omitted.

  def payouts(market)
    nets = market.ledger_entries.group(:membership_id).sum(:amount_cents).reject { |_, cents| cents.zero? }
    names = @group.memberships.where(id: nets.keys).joins(:user).pluck(:id, "users.name").to_h
    nets.sort_by { |id, cents| [-cents, id] }.map { |id, cents| {membership_id: id, name: names[id], net_cents: cents} }
  end

  # @return [Array<Hash>] Each active member's balance in minor units of the
  #   group's currency (`membership_id`, `name`, `balance_cents`), largest
  #   creditors first.

  def balances
    amounts = Groups::BalanceSheet.new(@group).balances
    names = @group.memberships.where(id: amounts.keys).joins(:user).pluck(:id, "users.name").to_h
    amounts.sort_by { |id, cents| [-cents, id] }.map { |id, cents| {membership_id: id, name: names[id], balance_cents: cents} }
  end

  # @return [Hash] The payments that would settle the group's balances
  #   (`transfers`, each with the payee's payment handles), with the group's
  #   `currency` and an explanatory `note`. Suggestions never move money or
  #   change the ledger.

  def settle_up
    transfers = Groups::TransferSuggester.new(Groups::BalanceSheet.new(@group).balances).transfers
    payees = @group.memberships.where(id: transfers.map(&:payee_membership_id)).includes(:user).index_by(&:id)
    {currency: @group.currency, note: I18n.t("groups.settle_up.note", group: @group.name),
     transfers: transfers.map { it.to_h.merge(payee: payment_identity(payees.fetch(it.payee_membership_id))) }}
  end

  private

  def payment_identity(membership)
    user = membership.user
    {membership_id: membership.id, name: user.name, venmo_handle: user.venmo_handle,
     paypal_handle: user.paypal_handle, cashapp_cashtag: user.cashapp_cashtag}
  end
end
