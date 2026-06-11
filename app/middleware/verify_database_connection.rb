# frozen_string_literal: true

# Verifies the ActiveRecord connection is alive before each request.
#
# Rationale: Fly suspends the VM after idle; during suspend the OS clock
# pauses, so Rails's `idle_timeout` never fires and TCP keepalives don't
# detect dead sockets. On resume, pooled connections may point at a Neon
# branch that has also auto-suspended. `verify!` sends a cheap ping and
# reconnects if the socket is dead — absorbing the Neon cold-start cost
# here instead of letting it bubble up as a 504 at the Fly proxy.
#
# Skips Fly's health-check path so we don't add DB work to /up polls.

class VerifyDatabaseConnection
  SKIP_PATHS = ["/up"].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    ActiveRecord::Base.connection.verify! unless SKIP_PATHS.include?(env["PATH_INFO"])
    @app.call(env)
  end
end
