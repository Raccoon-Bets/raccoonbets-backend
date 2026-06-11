# frozen_string_literal: true

# List-item representation of a {Market}: outcomes with per-outcome pool totals
# and position counts, the total pool, and the viewing member's own position. All
# amounts are minor units of `currency`.
#
# Params
# ------
#
# |             |                                                                      |
# |:------------|:----------------------------------------------------------------------|
# | `:pools`    | `Position.pool_by_outcome` totals for the serialized markets.       |
# | `:my_positions`  | The viewing member's {Position}s, indexed by market ID.        |
# | `:currency` | The group's ISO 4217 currency code.                                  |

class MarketSerializer < ApplicationSerializer
  attributes :id, :title, :status, :locks_at, :created_at, :winning_outcome_id, :resolved_at

  attribute :locked, &:locked?

  attribute :currency do
    params[:currency]
  end

  attribute :creator do |market|
    membership_ref market.creator
  end

  attribute :oracle do |market|
    membership_ref market.oracle
  end

  attribute :outcomes do |market|
    market.outcomes.map do |outcome|
      {id: outcome.id, name: outcome.name, position: outcome.position, **pool_for(outcome)}
    end
  end

  attribute :total_pool_cents do |market|
    market.outcomes.sum { |outcome| pool_for(outcome)[:pool_cents] }
  end

  attribute :my_position do |market|
    position = params[:my_positions]&.[](market.id)
    position && {id: position.id, outcome_id: position.outcome_id, amount_cents: position.amount_cents}
  end

  private

  def membership_ref(membership)
    {id: membership.id, name: membership.user.name}
  end

  def pool_for(outcome)
    params[:pools]&.[](outcome.id) || {pool_cents: 0, position_count: 0}
  end
end
