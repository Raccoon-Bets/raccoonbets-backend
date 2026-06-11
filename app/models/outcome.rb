# frozen_string_literal: true

# An Outcome is one of the two or more possible results of a {Market} that
# members trade on. A binary market is simply two outcomes named YES and NO — no
# special-casing. Outcomes are created with their market and become immutable
# once any {Position} exists on the market.
#
# Associations
# ------------
#
# |             |                                       |
# |:------------|:---------------------------------------|
# | `market`    | The {Market} this outcome is for.      |
# | `positions` | The {Position}s on this outcome.       |
#
# Properties
# ----------
#
# |            |                                                          |
# |:-----------|:----------------------------------------------------------|
# | `name`     | The outcome's label, unique within the market.           |
# | `position` | The outcome's display order, unique within the market.   |

class Outcome < ApplicationRecord
  belongs_to :market, inverse_of: :outcomes
  has_many :positions, dependent: :destroy

  validates :name,
            presence:   true,
            uniqueness: {scope: :market_id}
  validates :position,
            presence:     true,
            numericality: {only_integer: true, greater_than_or_equal_to: 0},
            uniqueness:   {scope: :market_id}
  validate :unchangeable_once_positions_exist, on: :update

  private

  def unchangeable_once_positions_exist
    return unless market.positions.exists?

    errors.add(:name, :unchangeable) if name_changed?
    errors.add(:position, :unchangeable) if position_changed?
  end
end
