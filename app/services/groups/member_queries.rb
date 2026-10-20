# frozen_string_literal: true

# Member-visible market and financial data shared by REST and MCP.
class Groups::MemberQueries
  # @param membership [Membership] the viewer whose position appears in results.
  def initialize(membership)
    @membership = membership
    @group = membership.group
  end

  # Returns markets in feed order, optionally restricted by trading status.
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

  # Loads a group-scoped market with the associations used by its detail serializer.
  def market(id)
    @group.markets.includes(:outcomes, positions: {membership: :user}, creator: :user, oracle: :user,
                            resolved_by: :user, market_events: [:outcome, {actor: :user}],
                            comments: {author: :user}).find(id)
  end

  # Builds serializer context for the viewing member and current pools.
  def trading_context(markets)
    {pools: Position.pool_by_outcome(markets),
     my_positions: @membership.positions.where(market: markets).index_by(&:market_id), currency: @group.currency}
  end

  # Returns realized per-member payouts for a market, with zero nets omitted.
  def payouts(market)
    nets = market.ledger_entries.group(:membership_id).sum(:amount_cents).reject { |_, cents| cents.zero? }
    names = @group.memberships.where(id: nets.keys).joins(:user).pluck(:id, "users.name").to_h
    nets.sort_by { |id, cents| [-cents, id] }.map { |id, cents| {membership_id: id, name: names[id], net_cents: cents} }
  end

  # Returns group balances in minor units, largest creditors first.
  def balances
    amounts = Groups::BalanceSheet.new(@group).balances
    names = @group.memberships.where(id: amounts.keys).joins(:user).pluck(:id, "users.name").to_h
    amounts.sort_by { |id, cents| [-cents, id] }.map { |id, cents| {membership_id: id, name: names[id], balance_cents: cents} }
  end

  # Suggests payments without initiating transfers or altering the ledger.
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
