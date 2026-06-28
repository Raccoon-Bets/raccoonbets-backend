# frozen_string_literal: true

# Skip metrics in test/cypress environments
return if Rails.env.test? || Rails.env.cypress?

require "yabeda/prometheus"

# Cache User.count so Prometheus scrapes (~every 15s) query Postgres at most once
# per interval, letting the database idle between scrapes.
users_total_ttl = 15.minutes.to_i
users_total = nil
users_total_at = nil

Yabeda.configure do
  group :raccoonbets do
    gauge :users_total,
          comment: "Total number of registered users",
          tags:    []
  end

  collect do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if users_total.nil? || now - users_total_at >= users_total_ttl
      users_total = User.count
      users_total_at = now
    end
    raccoonbets.users_total.set({}, users_total)
  end
end

Yabeda.configure!
