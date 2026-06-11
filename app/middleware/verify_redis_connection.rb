# frozen_string_literal: true

# Verifies the Rack::Attack Redis connection is alive before each request.
#
# Rationale: Fly suspends the VM after idle; the OS clock pauses, so TCP
# keepalives don't reap dead sockets and the redis-client connection pool
# still hands out the stale socket on resume. Rack::Attack runs early in
# the middleware stack, so its first read/write after a resume blocks past
# Fly's proxy timeout (504). Pinging here lets redis-client detect the dead
# socket on send and reconnect, absorbing the cost on this side instead of
# letting it bubble up as a 504.
#
# Skips Fly's health-check path. Errors are swallowed: rack-attack falls
# open on cache failures by design, and a transient Redis blip should not
# 500 the site.

class VerifyRedisConnection

  SKIP_PATHS = ["/up"].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    ping_redis unless SKIP_PATHS.include?(env["PATH_INFO"])
    @app.call(env)
  end

  private

  def ping_redis
    store = Rack::Attack.cache.store
    return unless store.kind_of?(ActiveSupport::Cache::RedisCacheStore)

    store.redis.ping
  rescue StandardError => e
    Sentry.capture_message("Redis ping failed: #{e.class.name}: #{e.message}") if defined?(Sentry)
  end

end
