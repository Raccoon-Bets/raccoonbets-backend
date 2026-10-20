# frozen_string_literal: true

# The group-scoped assistant tools, acting as one active member through
# {Groups::MemberQueries} and {Groups::Participation}. Each public instance
# method implements the {Mcp::Tools} tool of the same name and takes that
# tool's arguments, apart from `group_id`, as keywords. Each returns
# JSON-compatible data; a record that fails validation raises
# `ActiveRecord::RecordInvalid`.

class Mcp::GroupTools
  # @param serializer [Class] An Alba serializer.
  # @param record [Object] The record or records to serialize.
  # @param params [Hash] The serializer's params.
  # @return [Hash, Array] The serialized JSON, parsed.

  def self.serialize(serializer, record, **params) = JSON.parse(serializer.new(record, params:).serialize)

  # @param membership [Membership] The active member the tools act as.

  def initialize(membership)
    @membership = membership
    @group = membership.group
    @queries = Groups::MemberQueries.new(membership)
    @actions = Groups::Participation.new(membership)
  end

  # Tool names are the method names, so the read tools keep their `get_`
  # prefix.
  # rubocop:disable Naming/AccessorMethodName

  # @return [Hash] The group's settings and currency, with the member's own
  #   membership.

  def get_group = serialize(GroupSerializer, @group, membership: @membership)

  # @return [Hash] The group's `currency` and every active member's `balances`.

  def get_balances = {currency: @group.currency, balances: @queries.balances}

  # @return [Hash] Payments that would settle the group's balances (see
  #   {Groups::MemberQueries#settle_up}).

  def get_settlement_suggestions = @queries.settle_up
  # rubocop:enable Naming/AccessorMethodName

  # @return [Array<Hash>] The group's active members, oldest first.

  def list_members = serialize(MembershipSerializer, @group.memberships.active.includes(:user).order(:created_at))

  # @param status [String, nil] Optional status filter (see
  #   {Groups::MemberQueries#markets}).
  # @param limit [Integer] The page size.
  # @param offset [Integer] How many markets to skip.
  # @return [Array<Hash>] One page of the group's markets in feed order.

  def list_markets(status: nil, limit: 50, offset: 0)
    markets = @queries.markets(status:).limit(limit).offset(offset)
    serialize(MarketSerializer, markets, **@queries.trading_context(markets))
  end

  # @param market_id [Integer] The market's ID within the group.
  # @return [Hash] The market's full detail.

  def get_market(market_id:) = market_detail(market_id)

  # @return [Array<Hash>] The group's 100 most recent settlements, voided ones
  #   included.

  def list_settlements
    records = @group.settlements.includes(payer: :user, payee: :user, recorded_by: :user).
        order(created_at: :desc, id: :desc).limit(100)
    serialize(SettlementSerializer, records, currency: @group.currency)
  end

  # @param outcomes [Array<String>] Outcome names, in display order.
  # @param attributes [Hash] Market attributes (see
  #   {Groups::Participation#create_market}).
  # @return [Hash] The new market's full detail.

  def create_market(outcomes:, **attributes)
    market_detail validated!(@actions.create_market(attributes, outcomes:)).id
  end

  # @param market_id [Integer] The market's ID within the group.
  # @param attributes [Hash] The market attributes to change.
  # @return [Hash] The market's full detail.

  def update_market(market_id:, **attributes)
    validated! @actions.update_market(market_id, attributes)
    market_detail market_id
  end

  # @param market_id [Integer] The market's ID within the group.
  # @param attributes [Hash] Position attributes (`outcome_id`, `amount_cents`).
  # @return [Hash] The member's position.

  def set_position(market_id:, **attributes)
    serialize(PositionSerializer, validated!(@actions.set_position(market_id, attributes)))
  end

  # @param market_id [Integer] The market's ID within the group.
  # @return [Hash] Confirmation of the cancellation.

  def cancel_position(market_id:)
    @actions.cancel_position(market_id)
    {cancelled: true, market_id:}
  end

  # @param market_id [Integer] The market's ID within the group.
  # @param body [String] The comment text.
  # @return [Hash] The market's full detail, including the new comment.

  def post_comment(market_id:, body:)
    validated! @actions.create_comment(market_id, {body:})
    market_detail market_id
  end

  # @param market_id [Integer] The market's ID within the group.
  # @param comment_id [Integer] The comment's ID within the market.
  # @return [Hash] The market's full detail.

  def delete_comment(market_id:, comment_id:)
    @actions.delete_comment(market_id, comment_id)
    market_detail market_id
  end

  # @param market_id [Integer] The market's ID within the group.
  # @param outcome_id [Integer] The winning outcome's ID.
  # @param effective_at [String, nil] When the outcome became known, for an
  #   early resolution.
  # @return [Hash] The resolved market's full detail.

  def resolve_market(market_id:, outcome_id:, effective_at: nil)
    @actions.resolve_market(market_id, outcome_id, effective_at:)
    market_detail market_id
  end

  # @param market_id [Integer] The market's ID within the group.
  # @return [Hash] The voided market's full detail.

  def void_market(market_id:)
    @actions.void_market(market_id)
    market_detail market_id
  end

  # @param attributes [Hash] Settlement attributes (see
  #   {Groups::Participation#record_settlement}).
  # @return [Hash] The recorded settlement.

  def record_settlement(**attributes)
    serialize(SettlementSerializer, validated!(@actions.record_settlement(attributes)), currency: @group.currency)
  end

  # @param settlement_id [Integer] The settlement's ID within the group.
  # @return [Hash] The voided settlement.

  def void_settlement(settlement_id:)
    serialize(SettlementSerializer, @actions.void_settlement(settlement_id), currency: @group.currency)
  end

  private

  def serialize(...) = self.class.serialize(...)

  def validated!(record)
    raise ActiveRecord::RecordInvalid, record if record.errors.any?

    record
  end

  def market_detail(id)
    market = @queries.market(id)
    serialize(MarketDetailSerializer, market, **@queries.trading_context([market]), payouts: @queries.payouts(market))
  end
end
