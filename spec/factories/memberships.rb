# frozen_string_literal: true

FactoryBot.define do
  factory :membership do
    user
    group

    role { "member" }
    status { "active" }

    trait :admin do
      role { "admin" }
    end

    trait :requested do
      status { "requested" }
    end
  end
end
