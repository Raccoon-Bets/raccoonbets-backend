# frozen_string_literal: true

# The actions one active member takes in their {Group}: creating and editing
# markets, trading, commenting, resolving, and recording settlements. Both the
# website API and the assistant tools ({Mcp::ToolContext}) act through it, so
# they share the same permission rules, broadcasts, and notifications.
#
# A denied action raises {Groups::ActionError}. A record that fails validation
# is returned unsaved, with its `errors` populated.

class Groups::Participation
  # The edited market fields position holders are told about.
  NOTIFIED_EDIT_FIELDS = %w[title description locks_at].freeze

  # @param membership [Membership] The member performing the actions.
  # @raise [Groups::ActionError] If the membership or its group is not active.

  def initialize(membership)
    @membership = membership
    @group = membership.group
    raise Groups::ActionError, "group_scoping.errors.not_a_member" unless membership.active? && @group.active?
  end

  # Creates a market with its outcomes, notifying the group once it is saved.
  # The oracle defaults to the creator.
  #
  # @param attributes [Hash] Market attributes (`title`, `description`,
  #   `locks_at`, `oracle_id`, `kind`).
  # @param outcomes [Array<String>] Outcome names, in display order.
  # @return [Market] The market, persisted if valid.

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

  # Edits an open market as its creator or a group admin. Every other position
  # holder is emailed about changes to the {NOTIFIED_EDIT_FIELDS}.
  #
  # @param market_id [Integer] The market's ID within the group.
  # @param attributes [Hash] Market attributes (`title`, `description`,
  #   `locks_at`).
  # @return [Market] The market, updated if valid.
  # @raise [Groups::ActionError] If the member may not edit the market, or it
  #   is no longer open.

  def update_market(market_id, attributes)
    market = editable_market(market_id)
    if market.update(attributes)
      GroupChannel.broadcast_event @group, :market_updated, market_id: market.id
      notify_position_holders_of_edit market
    end
    market
  end

  # Places or replaces the member's single position, locking the market so the
  # trade cannot race its resolution.
  #
  # @param market_id [Integer] The market's ID within the group.
  # @param attributes [Hash] Position attributes (`outcome_id`, `amount_cents`).
  # @return [Position] The position, saved if valid.

  def set_position(market_id, attributes)
    market = @group.markets.find(market_id)
    market.with_lock do
      position = market.positions.find_or_initialize_by(membership: @membership)
      position.update(attributes)
      position
    end
  end

  # Cancels the member's position while the market accepts trades.
  #
  # @param market_id [Integer] The market's ID within the group.
  # @return [Position] The destroyed position.
  # @raise [Groups::ActionError] If trading has closed.

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

  # Posts a comment on a market, notifying the group once it is saved.
  #
  # @param market_id [Integer] The market's ID within the group.
  # @param attributes [Hash] Comment attributes (`body`).
  # @return [Comment] The comment, persisted if valid.

  def create_comment(market_id, attributes)
    market = @group.markets.find(market_id)
    comment = market.comments.new(attributes)
    comment.author = @membership
    Notifications::DispatchJob.perform_later(event: "market_commented", record_id: comment.id) if comment.save
    comment
  end

  # Deletes a comment as its author or a group admin.
  #
  # @param market_id [Integer] The market's ID within the group.
  # @param comment_id [Integer] The comment's ID within the market.
  # @return [Comment] The destroyed comment.
  # @raise [Groups::ActionError] If the member may not delete the comment.

  def delete_comment(market_id, comment_id)
    comment = @group.markets.find(market_id).comments.find(comment_id)
    unless @membership.admin? || comment.author_membership_id == @membership.id
      raise Groups::ActionError, "groups.comments.errors.not_deletable"
    end

    comment.destroy!
    comment
  end

  # Resolves a market to a winning outcome as its oracle or a group admin
  # (see {Markets::Resolver.resolve}).
  #
  # @param market_id [Integer] The market's ID within the group.
  # @param outcome_id [Integer] The winning outcome's ID.
  # @param effective_at [String, Time, nil] When the outcome became known, for
  #   an early resolution.
  # @return [Market] The resolved market.
  # @raise [Groups::ActionError] If the member is neither oracle nor admin.
  # @raise [Markets::Resolver::Error] If `effective_at` is malformed or the
  #   market cannot be resolved.

  def resolve_market(market_id, outcome_id, effective_at: nil)
    market = resolvable_market(market_id)
    Markets::Resolver.resolve(market, market.outcomes.find(outcome_id), @membership,
                              effective_at: parse_effective_at(effective_at))
    market
  end

  # Voids a market as its oracle or a group admin, reversing any resolution
  # ledger entries (see {Markets::Resolver.void}).
  #
  # @param market_id [Integer] The market's ID within the group.
  # @return [Market] The voided market.
  # @raise [Groups::ActionError] If the member is neither oracle nor admin.
  # @raise [Markets::Resolver::Error] If the market cannot be voided.

  def void_market(market_id)
    market = resolvable_market(market_id)
    Markets::Resolver.void(market, @membership)
    market
  end

  # Records a payment made outside the app. It never moves money. The payer
  # defaults to the member, who must be a party to it unless they are a group
  # admin.
  #
  # @param attributes [Hash] Settlement attributes (`payer_membership_id`,
  #   `payee_membership_id`, `amount_cents`, `payment_method`, `note`).
  # @return [Settlement] The settlement, persisted if valid.
  # @raise [Groups::ActionError] If the member is neither a party nor an admin.

  def record_settlement(attributes)
    settlement = @group.settlements.new(attributes)
    settlement.payer_membership_id ||= @membership.id
    settlement.recorded_by = @membership
    require_party!(settlement)
    notify_settlement(settlement, "recorded") if settlement.save
    settlement
  end

  # Voids a settlement as a party to it or a group admin, keeping its history
  # and reversing its ledger entries.
  #
  # @param settlement_id [Integer] The settlement's ID within the group.
  # @return [Settlement] The voided settlement.
  # @raise [Groups::ActionError] If the member is neither a party nor an admin,
  #   or the settlement is already voided.

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

  def editable_market(id)
    market = @group.markets.find(id)
    raise Groups::ActionError, "groups.markets.errors.not_editor" unless editor?(market)
    raise Groups::ActionError.new("groups.markets.errors.not_open", status: :unprocessable_content) unless market.open?

    market
  end

  def editor?(market) = @membership.admin? || market.creator_id == @membership.id

  # Runs after the UPDATE has committed, so a rolled-back edit never mails
  # anyone.
  def notify_position_holders_of_edit(market)
    changes = market.saved_changes.slice(*NOTIFIED_EDIT_FIELDS)
    return if changes.empty?

    (market.position_holders - [@membership.user]).each do |user|
      AdminActionMailer.market_edited(user:, market:, changes:, actor_name: @membership.user.name).deliver_later
    end
  end

  def resolvable_market(id)
    market = @group.markets.find(id)
    unless @membership.admin? || market.oracle_id == @membership.id
      raise Groups::ActionError, "group_scoping.errors.not_oracle_or_admin"
    end

    market
  end

  # Maps a malformed timestamp to the same error the resolver's own guards
  # raise.
  def parse_effective_at(value)
    return if value.blank?

    Time.zone.parse(value.to_s) or raise_effective_at_invalid
  rescue ArgumentError
    raise_effective_at_invalid
  end

  def raise_effective_at_invalid
    raise Markets::Resolver::Error, I18n.t("markets.resolver.errors.effective_at_invalid")
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
