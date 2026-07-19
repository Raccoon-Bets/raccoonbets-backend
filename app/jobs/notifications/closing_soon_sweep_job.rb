# frozen_string_literal: true

module Notifications
  # Safety net for {ClosingSoonNotifyJob}. Runs daily and re-enqueues the notice
  # for every open, un-notified market whose lock time falls within {HORIZON},
  # so a per-market job lost from the queue (e.g. a Redis flush) is restored well
  # before it is due. Duplicate enqueues are harmless — the notify job is
  # idempotent.
  class ClosingSoonSweepJob < ApplicationJob
    queue_as :default

    # Comfortably wider than the daily cadence so no market slips between sweeps.
    HORIZON = 2.days

    def perform
      Market.open.scheduled.
          where(closing_soon_notified_at: nil, locks_at: Time.current..HORIZON.from_now).
          find_each do |market|
        ClosingSoonNotifyJob.set(wait_until: market.locks_at - Market::CLOSING_SOON_WINDOW).perform_later(market.id)
      end
    end
  end
end
