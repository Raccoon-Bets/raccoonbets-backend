# frozen_string_literal: true

# Verifies the ActiveRecord connection is alive before each request.
#
# Rationale: Fly suspends the VM after idle; during suspend the OS clock
# pauses, so Rails's `idle_timeout` never fires and TCP keepalives don't
# detect dead sockets. `verify!` sends a cheap ping and reconnects if the
# socket is dead, absorbing that cost here instead of letting it bubble up
# as a 504 at the Fly proxy.
#
# Skips Fly's health-check and metrics paths. Both are polled continuously
# (/up every 10s, /metrics every 15s), so there is never a stale socket to
# recover on them, and verifying would ping Postgres on every poll.

class VerifyDatabaseConnection
  SKIP_PATHS = ["/up", "/metrics"].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    ActiveRecord::Base.connection.verify! unless SKIP_PATHS.include?(env["PATH_INFO"])
    @app.call(env)
  end
end
