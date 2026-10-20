# frozen_string_literal: true

# Request-local identity, consent, and result mapping for member tools.
class Mcp::ToolContext
  # @param token [Oauth::AccessToken] a validated bearer credential for this request.
  def initialize(token)
    @token = token
    @connection = token.mcp_connection
  end

  # Executes a declared tool within current consent and membership restrictions.
  def call(name, arguments, write:)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Groups::ActionError, "group_scoping.errors.not_a_member" unless @connection.reload.active?
    if write && (@token.scopes.exclude?("mcp:write") || @connection.scopes.split.exclude?("mcp:write"))
      return result = response({error: "This connection has read-only access."}, error: true)
    end

    data = if name == "list_groups"
             serialize(GroupSerializer, @connection.accessible_groups.order(:name))
           else
             group = @connection.accessible_groups.find_by!(subdomain: arguments.fetch(:group_id))
             membership = group.memberships.active.find_by!(user_id: @connection.user_id)
             perform(name, arguments.except(:group_id), membership)
           end
    result = response({data:})
  rescue ActiveRecord::RecordNotFound
    result = response({error: "The requested record is not available in an authorized group."}, error: true)
  rescue Groups::ActionError, Markets::Resolver::Error => e
    result = response({error: e.message}, error: true)
  rescue ActiveRecord::RecordInvalid => e
    result = response({errors: e.record.errors.to_hash}, error: true)
  ensure
    Rails.logger.info({event: "mcp.tool", tool: name, connection_id: @connection.id, user_id: @connection.user_id,
                       group: arguments[:group_id], success: result && !result.error?,
                       duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round}.to_json)
  end

  private

  def perform(name, args, member)
    queries = Groups::MemberQueries.new(member)
    actions = Groups::Participation.new(member)
    group = member.group
    case name
      when "get_group" then serialize(GroupSerializer, group, membership: member)
      when "list_members" then serialize(MembershipSerializer, group.memberships.active.includes(:user).order(:created_at))
      when "list_markets"
        markets = queries.markets(status: args[:status]).limit(args.fetch(:limit, 50)).offset(args.fetch(:offset, 0))
        serialize(MarketSerializer, markets, **queries.trading_context(markets))
      when "get_market" then market_detail(queries, args.fetch(:market_id))
      when "get_balances" then {currency: group.currency, balances: queries.balances}
      when "get_settlement_suggestions" then queries.settle_up
      when "list_settlements"
        records = group.settlements.includes(payer: :user, payee: :user, recorded_by: :user).order(created_at: :desc, id: :desc).limit(100)
        serialize(SettlementSerializer, records, currency: group.currency)
      else perform_write(name, args, actions, queries, group)
    end
  end

  def perform_write(name, args, actions, queries, group)
    market_id = args[:market_id]
    case name
      when "create_market"
        record = actions.create_market(args.except(:outcomes), outcomes: args.fetch(:outcomes))
        validate!(record)
        market_detail(queries, record.id)
      when "update_market"
        validate!(actions.update_market(market_id, args.except(:market_id)))
        market_detail(queries, market_id)
      when "set_position"
        record = actions.set_position(market_id, args.slice(:outcome_id, :amount_cents))
        validate!(record)
        serialize(PositionSerializer, record)
      when "cancel_position"
        actions.cancel_position(market_id)
        {cancelled: true, market_id:}
      when "post_comment"
        validate!(actions.create_comment(market_id, args.slice(:body)))
        market_detail(queries, market_id)
      when "delete_comment"
        actions.delete_comment(market_id, args.fetch(:comment_id))
        market_detail(queries, market_id)
      when "resolve_market"
        actions.resolve_market(market_id, args.fetch(:outcome_id), effective_at: parse_time(args[:effective_at]))
        market_detail(queries, market_id)
      when "void_market"
        actions.void_market(market_id)
        market_detail(queries, market_id)
      when "record_settlement"
        record = actions.record_settlement(args)
        validate!(record)
        serialize(SettlementSerializer, record, currency: group.currency)
      when "void_settlement"
        serialize(SettlementSerializer, actions.void_settlement(args.fetch(:settlement_id)), currency: group.currency)
    end
  end

  def validate!(record)
    raise ActiveRecord::RecordInvalid, record if record.errors.any?
  end

  def market_detail(queries, id)
    market = queries.market(id)
    serialize(MarketDetailSerializer, market, **queries.trading_context([market]), payouts: queries.payouts(market))
  end

  def parse_time(value)
    Time.iso8601(value) if value
  rescue ArgumentError
    raise Groups::ActionError.new("markets.resolver.errors.effective_at_invalid", status: :unprocessable_content)
  end

  def serialize(serializer, record, **params)
    JSON.parse(serializer.new(record, params:).serialize)
  end

  def response(data, error: false)
    MCP::Tool::Response.new([{type: "text", text: data.to_json}], error:, structured_content: data)
  end
end
