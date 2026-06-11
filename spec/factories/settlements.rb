# frozen_string_literal: true

FactoryBot.define do
  factory :settlement do
    group
    payer { association :membership, group: }
    payee { association :membership, group: }
    recorded_by { payer }
    amount_cents { 500 }
    payment_method { "venmo" }
  end
end
