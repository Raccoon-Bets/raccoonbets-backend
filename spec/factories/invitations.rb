# frozen_string_literal: true

FactoryBot.define do
  factory :invitation do
    group
    inviter factory: %i[user]

    sequence(:email) { |i| "invitee-#{i}@example.com" }
    role { "member" }

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :accepted do
      accepted_at { 1.hour.ago }
    end
  end
end
