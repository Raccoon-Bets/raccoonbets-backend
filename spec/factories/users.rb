# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    sequence(:email) { |i| "email-#{i}@example.com" }
    password { Faker::Internet.password }
    status_id { 2 }

    trait :unverified do
      status_id { 1 }
    end

    trait :superadmin do
      superadmin { true }
    end
  end
end
