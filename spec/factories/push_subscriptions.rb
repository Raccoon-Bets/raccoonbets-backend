# frozen_string_literal: true

FactoryBot.define do
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://push.example.com/sub/#{n}" }
    p256dh_key { "BPpublic_key_bytes" }
    auth_key { "auth_secret" }
    user_agent { "Mozilla/5.0" }
  end
end
