# frozen_string_literal: true

# Sidekiq keeps its keyspace on a dedicated Redis logical database (db 2) so it
# does not collide with the Rack::Attack cache (db 0).
redis = {url: ENV.fetch("SIDEKIQ_REDIS_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/2") }}

Sidekiq.configure_server do |config|
  config.redis = redis

  config.on(:startup) do
    CronSchedule.reconcile!(YAML.load_file(Rails.root.join("config", "schedule.yml")))
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis
end
