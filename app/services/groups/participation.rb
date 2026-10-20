# frozen_string_literal: true

# Member operations shared by the website API and assistant tools.
class Groups::Participation
  # @param membership [Membership] the active member performing the action.
  def initialize(membership)
    @membership = membership
    @group = membership.group
    raise Groups::ActionError, "group_scoping.errors.not_a_member" unless membership.active? && @group.active?
  end

  # Creates a market and ordered outcomes, notifying the group after persistence.
  def create_market(attributes, outcomes:)
    market = @group.markets.new(attributes)
    market.creator = @membership
    market.oracle_id ||= @membership.id
    Array(outcomes).each_with_index { |name, position| market.outcomes.build(name: name.to_s, position:) }
    if market.save
      GroupChannel.broadcast_event @group, :market_created, market_id: market.id
      Notifications::DispatchJob.perform_later(event: "market_created", record_id: market.id)
    end
    market
  end

  # Edits an open market as its creator or an admin, notifying other traders.
  def update_market(market_id, attributes)
    market = @group.markets.find(market_id)
    unless @membership.admin? || market.creator_id == @membership.id
      raise Groups::ActionError, "groups.markets.errors.not_editor"
    end
    raise Groups::ActionError.new("groups.markets.errors.not_open", status: :unprocessable_content) unless market.open?

    if market.update(attributes)
      GroupChannel.broadcast_event @group, :market_updated, market_id: market.id
      changes = market.saved_changes.slice("title", "description", "locks_at")
      if changes.any?
        recipients = market.positions.includes(membership: :user).map { it.membership.user }.uniq - [@membership.user]
        recipients.each do |user|
          AdminActionMailer.market_edited(user:, market:, changes:, actor_name: @membership.user.name).deliver_later
        end
      end
    end
    market
  end

  # Upserts the caller's position while serializing against market resolution.
  def set_position(market_id, attributes)
    market = @group.markets.find(market_id)
    market.with_lock do
      position = market.positions.find_or_initialize_by(membership: @membership)
      position.update(attributes)
      position
    end
  end

  # Cancels the caller's position while the market accepts trades.
  def cancel_position(market_id)
    market = @group.markets.find(market_id)
    market.with_lock do
      position = market.positions.find_by!(membership: @membership)
      position.destroy if market.open_for_trading?
      unless position.destroyed?
        raise Groups::ActionError.new("groups.positions.errors.trading_closed", status: :unprocessable_content)
      end

      position
    end
  end

  # Posts a comment and schedules the existing notification flow.
  def create_comment(market_id, attributes)
    market = @group.markets.find(market_id)
    comment = market.comments.new(attributes)
    comment.author = @membership
    Notifications::DispatchJob.perform_later(event: "market_commented", record_id: comment.id) if comment.save
    comment
  end

  # Deletes a comment as its author or a group admin.
  def delete_comment(market_id, comment_id)
    comment = @group.markets.find(market_id).comments.find(comment_id)
    unless @membership.admin? || comment.author_membership_id == @membership.id
      raise Groups::ActionError, "groups.comments.errors.not_deletable"
    end

    comment.destroy!
    comment
  end

  # Resolves a market as its oracle or a group admin using the shared ledger service.
  def resolve_market(market_id, outcome_id, effective_at: nil)
    market = resolvable_market(market_id)
    Markets::Resolver.resolve(market, market.outcomes.find(outcome_id), @membership, effective_at:)
    market
  end

  # Voids a market as its oracle or a group admin, preserving ledger reversals.
  def void_market(market_id)
    market = resolvable_market(market_id)
    Markets::Resolver.void(market, @membership)
    market
  end

  # Records an external payment; this operation never initiates a money transfer.
  def record_settlement(attributes)
    settlement = @group.settlements.new(attributes)
    settlement.payer_membership_id ||= @membership.id
    settlement.recorded_by = @membership
    require_party!(settlement)
    notify_settlement(settlement, "recorded") if settlement.save
    settlement
  end

  # Voids a settlement, retaining its history and reversing its ledger entries.
  def void_settlement(settlement_id)
    settlement = @group.settlements.find(settlement_id)
    require_party!(settlement)
    if settlement.voided?
      raise Groups::ActionError.new("groups.settlements.errors.already_voided", status: :unprocessable_content)
    end

    settlement.void!
    notify_settlement(settlement, "voided")
    settlement
  end

  private

  def resolvable_market(id)
    market = @group.markets.find(id)
    unless @membership.admin? || market.oracle_id == @membership.id
      raise Groups::ActionError, "group_scoping.errors.not_oracle_or_admin"
    end

    market
  end

  def require_party!(settlement)
    return if @membership.admin? || [settlement.payer_membership_id, settlement.payee_membership_id].include?(@membership.id)

    raise Groups::ActionError, "groups.settlements.errors.not_a_party"
  end

  def notify_settlement(settlement, kind)
    GroupChannel.broadcast_event @group, :"settlement_#{kind}"
    Notifications::DispatchJob.perform_later(event: "settlement", record_id: settlement.id, kind:)
  end
end
