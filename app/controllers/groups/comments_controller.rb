# frozen_string_literal: true

# Member discussion on a {Market}. Any active member can post a comment at any
# point in the market's life — open, resolved, or voided; the author can delete
# their own and a group admin can delete anyone's. Comments are never edited.
# Both actions broadcast over {MarketChannel} and respond with the refreshed
# market detail, so the client can replace its loaded market wholesale.

class Groups::CommentsController < ApplicationController
  include GroupScoping
  include Groups::TradingContext

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :find_market

  # Posts a comment to the market. Any active member, any market state.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/markets/:market_id/comments.json`
  #
  # Body Parameters
  # ---------------
  #
  # |            |                                          |
  # |:-----------|:------------------------------------------|
  # | `:comment` | Parameterized Comment attributes (`body`). |

  def create
    @comment = @market.comments.new(comment_params)
    @comment.author = current_membership
    if @comment.save
      Notifications::DispatchJob.perform_later(event: "market_commented", record_id: @comment.id)
      render_market_detail
    else
      render json: {errors: @comment.errors}, status: :unprocessable_content
    end
  end

  # Deletes a comment. The author or a group admin only.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/markets/:market_id/comments/:id.json`

  def destroy
    @comment = @market.comments.find(params.expect(:id))
    return render_not_deletable unless can_delete?(@comment)

    @comment.destroy
    render_market_detail
  end

  private

  def find_market
    @market = current_group.markets.find(params.expect(:market_id))
  end

  def comment_params = params.expect(comment: %i[body])

  def can_delete?(comment)
    current_membership.admin? || comment.author_membership_id == current_membership.id
  end

  # Re-renders the same payload as `GET /markets/:id`, so the store can replace
  # its loaded market (comments, pools, positions all consistent).
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

  def render_not_deletable
    render json:   {error: I18n.t("groups.comments.errors.not_deletable")},
           status: :forbidden
  end
end
