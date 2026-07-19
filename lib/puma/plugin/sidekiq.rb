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

    # Puma fires after_stopped from inside its SIGTERM trap handler, and
    # Sidekiq's shutdown acquires a Mutex (via connection_pool), which Ruby
    # forbids in a trap context. Stopping on a fresh thread escapes the trap;
    # joining keeps shutdown graceful so in-flight jobs still drain.
    launcher.events.after_stopped { Thread.new { @sidekiq&.stop }.join }
  end
end
