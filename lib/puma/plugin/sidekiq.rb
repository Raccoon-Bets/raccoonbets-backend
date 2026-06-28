# frozen_string_literal: true

require "puma/plugin"

# Runs Sidekiq embedded in the Puma process so background jobs run without a
# dedicated worker machine. Redis and the cron schedule come from
# config/initializers/sidekiq.rb; Sidekiq.configure_embed re-applies those
# configure_server blocks to the embedded config. Starting in after_booted
# ensures the Rails application (and the Sidekiq Railtie) has loaded first.
Puma::Plugin.create do
  def start(launcher)
    launcher.events.after_booted do
      @sidekiq = Sidekiq.configure_embed do |config|
        config.concurrency = 2
        config.queues = %w[default mailers]
      end
      @sidekiq.run
    end

    launcher.events.after_stopped { @sidekiq&.stop }
  end
end
