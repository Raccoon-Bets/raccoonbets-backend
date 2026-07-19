# frozen_string_literal: true

# Loads sidekiq-cron schedules and prunes any previously-registered job that is
# no longer defined. sidekiq-cron persists jobs in Redis and `load_from_hash!`
# only adds or updates them, so without this a renamed or removed schedule would
# linger and keep firing against a class that no longer exists.
module CronSchedule
  extend self

  def reconcile!(schedule)
    Sidekiq::Cron::Job.load_from_hash!(schedule)
    stale_job_names(schedule).each { |name| Sidekiq::Cron::Job.destroy(name) }
  end

  private

  def stale_job_names(schedule)
    Sidekiq::Cron::Job.all.map(&:name) - schedule.keys
  end
end
