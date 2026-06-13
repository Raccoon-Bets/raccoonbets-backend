# frozen_string_literal: true

# Singular-resource controller for a {Market}'s resolution, delegating to
# {Markets::Resolver}. The market's oracle or a group admin can resolve and
# void; only a group admin can correct. All three respond with the updated
# market detail JSON (including the per-member payout summary and the audit
# trail); disallowed transitions render 422.

class Groups::ResolutionsController < ApplicationController
  include GroupScoping
  include Groups::TradingContext

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :find_market
  before_action :require_oracle_or_admin!, only: %i[create destroy]
  before_action :require_group_admin!, only: :update

  rescue_from Markets::Resolver::Error, with: :resolution_error

  # Resolves an open, locked market to an outcome, writing the win/loss ledger
  # entries. Oracle or group admin.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/markets/:market_id/resolution.json`
  #
  # Body Parameters
  # ---------------
  #
  # |               |                                 |
  # |:--------------|:----------------------------------|
  # | `:outcome_id` | The ID of the winning outcome.  |

  def create
    Markets::Resolver.resolve @market, outcome, current_membership
    render_market_detail
  end

  # Corrects a resolved market to a different outcome, reversing the live
  # ledger entries and replaying the payout. Group admin only.
  #
  # Routes
  # ------
  #
  # * `PUT /groups/:group_id/markets/:market_id/resolution.json`
  #
  # Body Parameters
  # ---------------
  #
  # |               |                                           |
  # |:--------------|:--------------------------------------------|
  # | `:outcome_id` | The ID of the corrected winning outcome. |

  def update
    Markets::Resolver.correct @market, outcome, current_membership
    render_market_detail
  end

  # Voids a market, reversing its ledger entries if it was resolved. Oracle or
  # group admin.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/markets/:market_id/resolution.json`

  def destroy
    Markets::Resolver.void @market, current_membership
    render_market_detail
  end

  private

  def find_market
    @market = current_group.markets.find(params.expect(:market_id))
  end

  def outcome = @market.outcomes.find(params.expect(:outcome_id))

  def render_market_detail
    @market = current_group.markets.
        includes(:outcomes, positions: {membership: :user}, creator: :user, oracle: :user,
                 resolved_by: :user, market_events: [:outcome, {actor: :user}],
                 comments: {author: :user}).
        find(@market.id)
    load_trading_context [@market]
    load_resolution_context @market
    render "groups/markets/show"
  end

  def resolution_error(error)
    render json: {error: error.message}, status: :unprocessable_content
  end
end
