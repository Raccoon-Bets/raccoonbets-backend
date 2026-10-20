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
    @position = Groups::Participation.new(current_membership).set_position(@market.id, position_params)
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
    @position = Groups::Participation.new(current_membership).cancel_position(@market.id)
    respond_with @position
  end

  private

  def find_market
    @market = current_group.markets.find(params.expect(:market_id))
  end

  def position_params = params.expect(position: %i[outcome_id amount_cents])
end
