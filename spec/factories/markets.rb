# frozen_string_literal: true

FactoryBot.define do
  factory :market do
    group
    creator { association :membership, group: }
    oracle { creator }
    title { "Will #{Faker::Name.first_name} #{Faker::Verb.base} in #{Date.current.year + 1}?" }
    locks_at { 1.day.from_now }

    transient do
      outcome_names { %w[YES NO] }
    end

    after(:build) do |market, context|
      next if market.outcomes.any?

      context.outcome_names.each_with_index { |name, position| market.outcomes.build(name:, position:) }
    end

    # locks_at is validated to be in the future, so locked/concluded markets
    # have to be created open and have their lock time backdated past
    # validations. Resolution and voiding then go through the real
    # Markets::Resolver transitions (ledger entries, market events and all).
    # rubocop:disable Rails/SkipsModelValidations
    trait :locked do
      after(:create) { |market| market.update_column(:locks_at, 1.hour.ago) }
    end

    trait :resolved do
      after(:create) do |market|
        market.update_column(:locks_at, 1.hour.ago)
        Markets::Resolver.resolve(market, market.outcomes.first, market.oracle)
      end
    end

    trait :voided do
      after(:create) { |market| Markets::Resolver.void(market, market.oracle) }
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
