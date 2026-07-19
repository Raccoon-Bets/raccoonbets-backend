# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::ClosingSoonNotifyJob do
  include ActiveJob::TestHelper

  let(:group) { create(:group) }

  it "dispatches and stamps a market inside the closing-soon window, exactly once" do
    market = create(:market, group:, locks_at: 30.minutes.from_now)

    expect do
      described_class.perform_now(market.id)
    end.to have_enqueued_job(Notifications::DispatchJob).
        with(event: "market_closing_soon", record_id: market.id)

    expect(market.reload.closing_soon_notified_at).to be_present

    # A duplicate or re-swept enqueue for the same market must not re-dispatch.
    expect { described_class.perform_now(market.id) }.not_to have_enqueued_job(Notifications::DispatchJob)
  end

  it "no-ops for a market still outside the window" do
    market = create(:market, group:, locks_at: 3.hours.from_now)

    expect { described_class.perform_now(market.id) }.not_to have_enqueued_job(Notifications::DispatchJob)
    expect(market.reload.closing_soon_notified_at).to be_nil
  end

  it "no-ops for a market whose trading has already locked" do
    market = create(:market, :locked, group:)

    expect { described_class.perform_now(market.id) }.not_to have_enqueued_job(Notifications::DispatchJob)
    expect(market.reload.closing_soon_notified_at).to be_nil
  end

  it "no-ops for a market that no longer exists" do
    expect { described_class.perform_now(-1) }.not_to have_enqueued_job(Notifications::DispatchJob)
  end
end
