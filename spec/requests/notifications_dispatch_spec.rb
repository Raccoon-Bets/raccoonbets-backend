# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notification dispatch hooks", type: :request do
  include ActiveJob::TestHelper

  let(:group) { create :group }
  let(:admin) { create :membership, :admin, group: }
  let(:payee) { create :membership, group: }
  let(:market) { create :market, group:, oracle: admin }
  let(:outcome) { market.outcomes.first }

  def lock!(market)
    market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
  end

  it "enqueues a dispatch when a market is created" do
    sign_in admin.user

    expect do
      post "/groups/#{group.to_param}/markets.json",
           params: {market: {title: "Will it?", description: "", locks_at: 1.day.from_now, outcomes: %w[Yes No]}}
    end.to have_enqueued_job(Notifications::DispatchJob).with(hash_including(event: "market_created"))
  end

  # The resolver registers its broadcast (and this dispatch enqueue) in an
  # `ActiveRecord.after_all_transactions_commit` hook. That hook fires while the
  # request is processed — the request's own transactions close before control
  # returns to the example — so the DispatchJob is enqueued during the `expect`
  # block and `have_enqueued_job` observes it directly. We must NOT
  # `perform_enqueued_jobs` here: doing so would drain the DispatchJob (running
  # its fan-out) and leave only downstream mailer jobs, making the matcher fail.
  it "enqueues a dispatch when a market resolves" do
    create(:position, market:, outcome:, amount_cents: 100)
    create(:position, market:, outcome: market.outcomes.second, amount_cents: 100)
    lock! market
    sign_in admin.user

    expect do
      post "/groups/#{group.to_param}/markets/#{market.id}/resolution.json", params: {outcome_id: outcome.id}
    end.to have_enqueued_job(Notifications::DispatchJob).
        with(hash_including(event: "market_resolved", record_id: market.id, kind: "resolved"))
  end

  it "enqueues a dispatch when a settlement is recorded" do
    sign_in admin.user

    expect do
      post "/groups/#{group.to_param}/settlements.json",
           params: {settlement: {payee_membership_id: payee.id, amount_cents: 500, payment_method: "venmo"}}
    end.to have_enqueued_job(Notifications::DispatchJob).with(hash_including(event: "settlement", kind: "recorded"))
  end

  it "enqueues a dispatch when a settlement is voided" do
    settlement = create(:settlement, group:, payer: admin, payee:, recorded_by: admin)
    sign_in admin.user

    expect do
      delete "/groups/#{group.to_param}/settlements/#{settlement.id}.json"
    end.to have_enqueued_job(Notifications::DispatchJob).
        with(hash_including(event: "settlement", record_id: settlement.id, kind: "voided"))
  end
end
