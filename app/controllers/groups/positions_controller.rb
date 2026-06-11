# frozen_string_literal: true

# Singular-resource controller for the current member's {Position} on a
# {Market}. Members hold at most one position per market: `PUT` upserts it
# (placing it or changing its outcome or amount) and `DELETE` cancels it, both
# only while the market is {Market#open_for_trading?}.

class Groups::PositionsController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :find_market

  # Places or updates the member's position on the market.
  #
  # Routes
  # ------
  #
  # * `PUT /groups/:group_id/markets/:market_id/position.json`
  #
  # Body Parameters
  # ---------------
  #
  # |             |                                                          |
  # |:------------|:----------------------------------------------------------|
  # | `:position` | Parameterized Position attributes (`outcome_id`, `amount_cents`). |

  def update
    # The market's row lock serializes positions against {Markets::Resolver},
    # which resolves under the same lock: the lock-time validation always sees
    # the market's committed state, so no position can slip into a resolving
    # market.
    @market.with_lock do
      @position = @market.positions.find_or_initialize_by(membership: current_membership)
      @position.update position_params
    end
    respond_with @position
  end

  # Cancels the member's position on the market. Allowed only while the market
  # is open for trading.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/markets/:market_id/position.json`

  def destroy
    @market.with_lock do
      @position = @market.positions.find_by!(membership: current_membership)
      @position.destroy if @market.open_for_trading?
    end
    return render_trading_closed unless @position.destroyed?

    respond_with @position
  end

  private

  def find_market
    @market = current_group.markets.find(params.expect(:market_id))
  end

  def position_params = params.expect(position: %i[outcome_id amount_cents])

  def render_trading_closed
    render json:   {error: I18n.t("groups.positions.errors.trading_closed")},
           status: :unprocessable_content
  end
end
