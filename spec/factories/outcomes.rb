# frozen_string_literal: true

FactoryBot.define do
  factory :outcome do
    market
    sequence(:name) { |i| "Outcome #{i}" }
    position { market.outcomes.count }
  end
end
