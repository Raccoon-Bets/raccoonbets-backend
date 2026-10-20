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
  # | `:market` | Parameterized Market attributes (`title`, `description`, optional `oracle_id` and `kind`; `locks_at` is required for a `scheduled` market and omitted for an `open_ended` one) plus `outcomes`, an array of at least two outcome names. |

  def create
    @market = Groups::Participation.new(current_membership).create_market(market_params, outcomes: outcome_names)
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
    @market = Groups::Participation.new(current_membership).update_market(@market.id, market_params)
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
    recipients = @market.position_holders - [current_membership.user]
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
    @market = load_market_detail(params.expect(:id))
  end

  def market_params
    case action_name
      when "create" then params.expect(market: %i[title description locks_at oracle_id kind])
      else params.expect(market: %i[title description locks_at])
    end
  end

  def outcome_names = Array(params[:market][:outcomes]).map(&:to_s)

  def filtered_markets
    Groups::MemberQueries.new(current_membership).markets(status: params[:status])
  end
end
