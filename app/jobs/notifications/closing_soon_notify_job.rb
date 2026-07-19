# frozen_string_literal: true

module Notifications
  # Notifies on a single market that is about to lock. Scheduled at
  # `locks_at - Market::CLOSING_SOON_WINDOW` when the market's lock time is set
  # (see {Market#schedule_closing_soon_notification}) and re-enqueued by
  # {ClosingSoonSweepJob}. Idempotent: it re-checks the market at run time, so a
  # stale (postponed market) or duplicate (re-swept) enqueue simply no-ops.
  class ClosingSoonNotifyJob < ApplicationJob
    queue_as :default

    def perform(market_id)
      market = Market.find_by(id: market_id)
      return unless market&.closing_soon? && market.closing_soon_notified_at.nil?

      market.update_column(:closing_soon_notified_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      DispatchJob.perform_later(event: "market_closing_soon", record_id: market.id)
    end
  end
end
