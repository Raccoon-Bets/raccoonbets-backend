# frozen_string_literal: true

FactoryBot.define do
  factory :position do
    market
    outcome { market.outcomes.first }
    membership { association :membership, group: market.group }
    amount_cents { market.group.min_amount_cents }
  end
end
