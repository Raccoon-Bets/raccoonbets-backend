# frozen_string_literal: true

# RESTful controller for a {Group}'s {Market}s. Members only. Any active member
# can create a market; only its creator can edit it, and only while it is open.
#
# List and detail responses include per-outcome pool totals and the viewing
# member's own position; the detail response also includes every position with
# the trader's name.

class Groups::MarketsController < ApplicationController
  include GroupScoping
  include Groups::TradingContext

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :find_market, only: %i[show update]

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

  # Updates a market's `title` and `description` (and `locks_at`, until the
  # first position is placed). Creator only, while the market is open.
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
    return render_not_creator unless @market.creator_id == current_membership.id
    return render_not_open unless @market.open?

    GroupChannel.broadcast_event current_group, :market_updated, market_id: @market.id if @market.update(market_params)
    respond_with @market
  end

  private

  def find_market
    @market = current_group.markets.
        includes(:outcomes, positions: {membership: :user}, creator: :user, oracle: :user,
                 resolved_by: :user, market_events: [:outcome, {actor: :user}]).
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

  def render_not_creator
    render json:   {error: I18n.t("groups.markets.errors.not_creator")},
           status: :forbidden
  end

  def render_not_open
    render json:   {error: I18n.t("groups.markets.errors.not_open")},
           status: :unprocessable_content
  end
end
