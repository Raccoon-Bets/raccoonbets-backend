# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::DispatchJob do
  include ActiveJob::TestHelper

  let(:group) { create(:group) }
  let(:creator) { create(:membership, group:) }
  let(:holder) { create(:membership, group:) }
  let(:market) { create(:market, group:, creator:) }

  before(:each) { create(:position, market:, membership: holder, outcome: market.outcomes.first) }

  it "emails and pushes position holders when a market resolves, respecting prefs" do
    create(:push_subscription, user: holder.user)

    described_class.perform_now(event: "market_resolved", record_id: market.id, kind: "resolved")

    expect(enqueued_mail_for?(holder.user, :market_resolved)).to be(true)
    expect(enqueued_jobs.select { |j| j[:job] == WebPush::DeliverJob }).not_to be_empty
  end

  it "skips a channel the user disabled but still pushes" do
    holder.user.update!(notification_preferences: {"market_resolved" => {"email" => false}})
    create(:push_subscription, user: holder.user)

    described_class.perform_now(event: "market_resolved", record_id: market.id, kind: "resolved")

    expect(enqueued_jobs.select { |j| j[:job] == WebPush::DeliverJob }).not_to be_empty
    expect(enqueued_jobs.select { |j| j[:job] == ActionMailer::MailDeliveryJob }).to be_empty
  end

  it "notifies all active members except the creator on market_created" do
    other = create(:membership, group:)

    described_class.perform_now(event: "market_created", record_id: market.id)

    expect(enqueued_mail_for?(other.user, :market_created)).to be(true)
    expect(enqueued_mail_for?(creator.user, :market_created)).to be(false)
  end

  it "notifies active members except the creator and existing holders on market_closing_soon" do
    other = create(:membership, group:)

    described_class.perform_now(event: "market_closing_soon", record_id: market.id)

    expect(enqueued_mail_for?(other.user, :market_closing_soon)).to be(true)
    expect(enqueued_mail_for?(holder.user, :market_closing_soon)).to be(false)
    expect(enqueued_mail_for?(creator.user, :market_closing_soon)).to be(false)
  end

  it "notifies the creator and prior commenters except the new commenter on market_commented" do
    prior_commenter = create(:membership, group:)
    create(:comment, market:, author: prior_commenter)
    new_commenter = create(:membership, group:)
    comment = create(:comment, market:, author: new_commenter)

    described_class.perform_now(event: "market_commented", record_id: comment.id)

    expect(enqueued_mail_for?(creator.user, :market_commented)).to be(true)
    expect(enqueued_mail_for?(prior_commenter.user, :market_commented)).to be(true)
    expect(enqueued_mail_for?(new_commenter.user, :market_commented)).to be(false)
  end

  it "respects a disabled channel on market_commented" do
    creator.user.update!(notification_preferences: {"market_commented" => {"email" => false}})
    create(:push_subscription, user: creator.user)
    comment = create(:comment, market:, author: create(:membership, group:))

    described_class.perform_now(event: "market_commented", record_id: comment.id)

    expect(enqueued_mail_for?(creator.user, :market_commented)).to be(false)
    expect(enqueued_jobs.select { |j| j[:job] == WebPush::DeliverJob }).not_to be_empty
  end

  it "no-ops when the record is gone" do
    expect do
      described_class.perform_now(event: "market_resolved", record_id: -1, kind: "resolved")
    end.not_to change(enqueued_jobs, :size)
  end

  # Inspects the real enqueued ActionMailer::MailDeliveryJob args. The mailer is
  # non-parameterized, so its kwargs are serialized under args[3]["args"][0],
  # with each record represented by its GlobalID.
  def enqueued_mail_for?(user, mailer_method)
    enqueued_jobs.any? do |job|
      next false unless job[:job] == ActionMailer::MailDeliveryJob

      mailer_class, method_name, _delivery, kwargs = job[:args]
      next false unless mailer_class == "NotificationMailer" && method_name == mailer_method.to_s

      kwargs.fetch("args").first&.dig("user", "_aj_globalid") == user.to_global_id.to_s
    end
  end
end
