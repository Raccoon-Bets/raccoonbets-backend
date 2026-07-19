# frozen_string_literal: true

require "rails_helper"

RSpec.describe CronSchedule do
  describe ".reconcile!" do
    let(:schedule) do
      {"closing_soon_sweep" => {"cron" => "0 8 * * *", "class" => "Notifications::ClosingSoonSweepJob"}}
    end

    before(:each) { Sidekiq::Cron::Job.destroy_all! }
    after(:each)  { Sidekiq::Cron::Job.destroy_all! }

    it "registers the scheduled jobs" do
      described_class.reconcile!(schedule)
      expect(Sidekiq::Cron::Job.all.map(&:name)).to contain_exactly("closing_soon_sweep")
    end

    it "prunes a previously-registered job that is no longer scheduled" do
      Sidekiq::Cron::Job.create(name: "old_scan", cron: "*/15 * * * *", class: "Notifications::ClosingSoonSweepJob")

      described_class.reconcile!(schedule)

      names = Sidekiq::Cron::Job.all.map(&:name)
      expect(names).to include("closing_soon_sweep")
      expect(names).not_to include("old_scan")
    end
  end
end
