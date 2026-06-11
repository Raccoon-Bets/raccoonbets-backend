# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::ClosingSoonScanJob do
  include ActiveJob::TestHelper

  let(:group) { create(:group) }

  it "dispatches and stamps markets closing within the window, exactly once" do
    soon = create(:market, group:, locks_at: 30.minutes.from_now)
    create(:market, group:, locks_at: 3.hours.from_now) # outside window
    # Past lock: create with future locks_at, then backdate past validations.
    # rubocop:disable Rails/SkipsModelValidations
    past = create(:market, group:)
    past.update_column(:locks_at, 5.minutes.ago)
    # rubocop:enable Rails/SkipsModelValidations

    expect do
      described_class.perform_now
    end.to have_enqueued_job(Notifications::DispatchJob).
        with(event: "market_closing_soon", record_id: soon.id)

    expect(soon.reload.closing_soon_notified_at).to be_present

    # Second run does not re-dispatch the already-stamped market.
    expect { described_class.perform_now }.not_to have_enqueued_job(Notifications::DispatchJob)
  end
end
