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
    @comment = Groups::Participation.new(current_membership).create_comment(@market.id, comment_params)
    if @comment.persisted?
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
    @comment = Groups::Participation.new(current_membership).delete_comment(@market.id, params.expect(:id))
    render_market_detail
  end

  private

  def find_market
    @market = current_group.markets.find(params.expect(:market_id))
  end

  def comment_params = params.expect(comment: %i[body])
end
