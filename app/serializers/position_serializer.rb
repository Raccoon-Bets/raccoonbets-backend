# frozen_string_literal: true

# A {Position} with the holding member's name. Amounts are minor units of the
# group's currency.

class PositionSerializer < ApplicationSerializer
  attributes :id, :outcome_id, :amount_cents, :updated_at

  attribute :member do |position|
    {id: position.membership_id, name: position.membership.user.name}
  end
end
