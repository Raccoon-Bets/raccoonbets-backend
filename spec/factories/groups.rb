# frozen_string_literal: true

FactoryBot.define do
  factory :group do
    name { "#{Faker::Creature::Animal.name.capitalize} Den" }
    sequence(:subdomain) { |i| "den-#{i}" }
    currency { "USD" }

    trait :suspended do
      status { "suspended" }
    end
  end
end
