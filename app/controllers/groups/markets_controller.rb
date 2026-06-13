# frozen_string_literal: true

# RESTful controller for a {Group}'s {Market}s. Members only. Any active member
# can create a market; its creator or a group admin can edit it while it is
# open, and a group admin can delete it while no money has moved. When an edit
# or delete lands on a market with positions, every other position holder is
# emailed what happened ({AdminActionMailer}).
#
# List and detail responses include per-outcome pool totals and the viewing
# member's own position; the detail response also includes every position with
# the trader's name.

class Groups::MarketsController < ApplicationController
  include GroupScoping
  include Groups::TradingContext

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :find_market, only: %i[show update destroy]
  before_action :require_group_admin!, only: :destroy

  # The edited fields position holders are told about.
  NOTIFIED_EDIT_FIELDS = %w[title description locks_at].freeze

  # Lists the group's markets: open markets first by soonest `locks_at`, then
  # resolved and voided markets, most recently concluded first.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/markets.json`
  #
  # Query Parameters
  # ----------------
  #
  # |          |                                                                                        |
  # |:---------|:-----------------------------------------------------------------------------------------|
  # | `status` | Optional filter: `open`, `resolved`, `voided`, or `locked` (open but past `locks_at`). |

  def index
    @markets = filtered_markets.includes(:outcomes, creator: :user, oracle: :user)
    load_trading_context @markets
    respond_with @markets
  end

  # Displays a market in full: outcomes with pool totals, every position with
  # the trader's name, and the viewing member's own position.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/markets/:id.json`

  def show
    respond_with @market
  end

  # Creates a market with its outcomes. Any active member. Outcome positions
  # follow the order of the `outcomes` array; the oracle defaults to the
  # creator.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/markets.json`
  #
  # Body Parameters
  # ---------------
  #
  # |           |                                                                                                              |
  # |:----------|:-----------------------------------------------------------------------------------------------------------|
  # | `:market` | Parameterized Market attributes (`title`, `description`, `locks_at`, optional `oracle_id`) plus `outcomes`, an array of at least two outcome names. |

  def create
    @market         = current_group.markets.new(market_params)
    @market.creator = current_membership
    @market.oracle_id ||= current_membership.id
    outcome_names.each_with_index { |name, position| @market.outcomes.build(name:, position:) }

    @market.save
    if @market.persisted?
      GroupChannel.broadcast_event current_group, :market_created, market_id: @market.id
      Notifications::DispatchJob.perform_later(event: "market_created", record_id: @market.id)
    end
    load_trading_context [@market]
    respond_with @market
  end

  # Updates a market's `title`, `description`, and `locks_at`. Creator or
  # group admin, while the market is open. When the market has positions,
  # every other position holder is emailed a summary of what changed.
  #
  # Routes
  # ------
  #
  # * `PATCH /groups/:group_id/markets/:id.json`
  #
  # Body Parameters
  # ---------------
  #
  # |           |                                                                  |
  # |:----------|:------------------------------------------------------------------|
  # | `:market` | Parameterized Market attributes (`title`, `description`, `locks_at`). |

  def update
    return render_not_editor unless editor?
    return render_not_open unless @market.open?

    if @market.update(market_params)
      GroupChannel.broadcast_event current_group, :market_updated, market_id: @market.id
      notify_position_holders_of_edit
    end
    respond_with @market
  end

  # Deletes a market that has not touched money, cascading its positions.
  # Group admins only. Every position holder except the acting admin is
  # emailed. A market with ledger entries (resolved, or voided after
  # resolution) cannot be deleted — the model's ledger restriction renders
  # 422; the existing void/correct flows are the only paths once money has
  # moved.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/markets/:id.json`

  def destroy
    recipients = other_position_holders
    title      = @market.title
    if @market.destroy
      GroupChannel.broadcast_event current_group, :market_deleted, market_id: @market.id
      recipients.each do |user|
        AdminActionMailer.market_deleted(user:, group: current_group, market_title: title,
                                         actor_name: current_membership.user.name).deliver_later
      end
    end
    respond_with @market
  end

  private

  def find_market
    @market = current_group.markets.
        includes(:outcomes, positions: {membership: :user}, creator: :user, oracle: :user,
                 resolved_by: :user, market_events: [:outcome, {actor: :user}],
                 comments: {author: :user}).
        find(params.expect(:id))
    load_trading_context [@market]
    load_resolution_context @market
  end

  def market_params
    case action_name
      when "create" then params.expect(market: %i[title description locks_at oracle_id])
      else params.expect(market: %i[title description locks_at])
    end
  end

  def outcome_names = Array(params[:market][:outcomes]).map(&:to_s)

  def filtered_markets
    scope = current_group.markets
    scope = case params[:status]
              when "locked" then scope.open.where(locks_at: ..Time.current)
              when "open", "resolved", "voided" then scope.where(status: params[:status])
              else scope
            end
    scope.order(Arel.sql(<<~SQL.squish))
      CASE WHEN status = 'open' THEN 0 ELSE 1 END,
      CASE WHEN status = 'open' THEN locks_at END ASC,
      COALESCE(resolved_at, locks_at) DESC,
      id ASC
    SQL
  end

  def editor? = current_membership.admin? || @market.creator_id == current_membership.id

  # Enqueued only after the UPDATE has committed (the request runs outside
  # any wrapping transaction), so a rolled-back edit never mails anyone.
  def notify_position_holders_of_edit
    changes = @market.saved_changes.slice(*NOTIFIED_EDIT_FIELDS)
    return if changes.empty?

    other_position_holders.each do |user|
      AdminActionMailer.market_edited(user:, market: @market, changes:,
                                      actor_name: current_membership.user.name).deliver_later
    end
  end

  # Every position holder's user except the actor — the people an edit or
  # delete must be explained to.
  def other_position_holders
    @market.positions.includes(membership: :user).map { |position| position.membership.user }.uniq -
      [current_membership.user]
  end

  def render_not_editor
    render json:   {error: I18n.t("groups.markets.errors.not_editor")},
           status: :forbidden
  end

  def render_not_open
    render json:   {error: I18n.t("groups.markets.errors.not_open")},
           status: :unprocessable_content
  end
end
