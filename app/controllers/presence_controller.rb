# frozen_string_literal: true

# Lightweight warm-up endpoint. The Frontend pings GET /presence on auth-page
# mount so the Fly machine, the Postgres pool, and the Redis pool are all
# already warm by the time the user clicks submit. The work happens in the
# middleware stack: VerifyRedisConnection and VerifyDatabaseConnection both
# skip /up but not /presence, so a hit here exercises both pooled
# connections — letting redis-client and AR detect dead sockets and
# reconnect transparently.
#
# Distinct from /up (rails/health#show), which Fly's health checker hits and
# which is intentionally exempted from the verify-* middlewares to avoid
# adding DB/Redis work to every health probe.

class PresenceController < ApplicationController

  def show
    head :ok
  end

end
