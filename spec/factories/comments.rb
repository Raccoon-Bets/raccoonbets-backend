# frozen_string_literal: true

FactoryBot.define do
  factory :comment do
    market
    author { association :membership, group: market.group }
    body { Faker::Lorem.sentence }
  end
end
