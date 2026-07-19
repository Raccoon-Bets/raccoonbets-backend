# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::ClosingSoonSweepJob do
  include ActiveJob::TestHelper

  let(:group) { create(:group) }

  it "re-enqueues a notify job for each open, un-notified market locking within the horizon" do
    within   = create(:market, group:, locks_at: 6.hours.from_now)
    beyond   = create(:market, group:, locks_at: 5.days.from_now)
    notified = create(:market, group:, locks_at: 3.hours.from_now)
    notified.update_column(:closing_soon_notified_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

    # Isolate the sweep's enqueues from the ones the create-time hook queued.
    clear_enqueued_jobs

    described_class.perform_now

    expect(Notifications::ClosingSoonNotifyJob).to have_been_enqueued.
        with(within.id).at(within.reload.locks_at - Market::CLOSING_SOON_WINDOW)
    expect(Notifications::ClosingSoonNotifyJob).not_to have_been_enqueued.with(beyond.id)
    expect(Notifications::ClosingSoonNotifyJob).not_to have_been_enqueued.with(notified.id)
  end
end
