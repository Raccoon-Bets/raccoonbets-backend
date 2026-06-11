# frozen_string_literal: true

module Notifications
  # Recurring (every 5 min via config/recurring.yml). Notifies on open markets
  # whose lock time falls inside the next window and that haven't been notified.
  class ClosingSoonScanJob < ApplicationJob
    queue_as :default

    WINDOW = 60.minutes

    def perform
      Market.open.
          where(closing_soon_notified_at: nil).
          where.not(locks_at: nil).
          where(locks_at: Time.current..WINDOW.from_now).
          find_each do |market|
        market.update_column(:closing_soon_notified_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
        DispatchJob.perform_later(event: "market_closing_soon", record_id: market.id)
      end
    end
  end
end
