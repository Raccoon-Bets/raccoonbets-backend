# frozen_string_literal: true

# Admin-only cancellation of another member's {Position}. The singular
# `/position` resource stays member self-service; this plural route lets a
# group admin remove a position that shouldn't stand, only while the market
# is {Market#open_for_trading?}. The position's owner is always emailed,
# naming the acting admin ({AdminActionMailer#position_cancelled}).

class Groups::AdminPositionsController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :require_group_admin!
  before_action :find_market

  # Cancels any member's position on the market. Group admins only; allowed
  # only while the market is open for trading.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/markets/:market_id/positions/:id.json`

  def destroy
    @market.with_lock do
      @position = @market.positions.find(params.expect(:id))
      @position.destroy if @market.open_for_trading?
    end
    return render_trading_closed unless @position.destroyed?

    notify_owner
    respond_with @position
  end

  private

  def find_market
    @market = current_group.markets.find(params.expect(:market_id))
  end

  def notify_owner
    owner = @position.membership
    return if owner.id == current_membership.id

    AdminActionMailer.position_cancelled(user: owner.user, market: @market,
                                         actor_name:   current_membership.user.name,
                                         amount_cents: @position.amount_cents).deliver_later
  end

  def render_trading_closed
    render json:   {error: I18n.t("groups.positions.errors.trading_closed")},
           status: :unprocessable_content
  end
end
