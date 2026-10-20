# frozen_string_literal: true

# E2E suites sign up and log in many times against one server process, which
# would trip the per-IP throttles below; rate limiting isn't under test there.
Rack::Attack.enabled = false if Rails.env.cypress?

Rack::Attack.cache.store =
    if ENV["REDIS_URL"].present?
      ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL"))
    else
      ActiveSupport::Cache::MemoryStore.new
    end

Rack::Attack.throttle("signup/ip/hour", limit: 3, period: 1.hour) do |req|
  req.ip if req.path == "/signup" && req.post?
end

Rack::Attack.throttle("signup/ip/day", limit: 10, period: 1.day) do |req|
  req.ip if req.path == "/signup" && req.post?
end

Rack::Attack.throttle("login/ip", limit: 10, period: 5.minutes) do |req|
  req.ip if req.path == "/login" && req.post?
end

Rack::Attack.throttle("password-resets/ip", limit: 3, period: 1.hour) do |req|
  req.ip if req.path == "/password-resets" && req.post?
end

Rack::Attack.throttle("verify-account/ip", limit: 10, period: 1.hour) do |req|
  req.ip if req.path == "/verify-account" && req.post?
end

# Registering a push subscription happens once per login per device; a flood of
# them signals an attacker probing scraped endpoints for cross-user takeover.
Rack::Attack.throttle("push-subscriptions/ip", limit: 20, period: 1.hour) do |req|
  req.ip if req.path == "/account/push_subscriptions" && req.post?
end

Rack::Attack.throttle("oauth-registration/ip", limit: 20, period: 1.hour) do |req|
  req.ip if req.path == "/oauth/register" && req.post?
end

Rack::Attack.throttle("oauth/ip", limit: 60, period: 5.minutes) do |req|
  req.ip if req.path.start_with?("/oauth/") && %w[/oauth/register /oauth/token].exclude?(req.path)
end

# Hosted assistants exchange tokens for all their users from a few egress IPs
# under one client ID, so token requests are limited per presented code or
# refresh token, with a looser per-IP backstop.
Rack::Attack.throttle("oauth-token/credential", limit: 60, period: 5.minutes) do |req|
  next unless req.path == "/oauth/token" && req.post?

  credential = req.params["refresh_token"].presence || req.params["code"].presence
  credential ? Digest::SHA256.hexdigest(credential.to_s) : req.ip
end

Rack::Attack.throttle("oauth-token/ip", limit: 600, period: 5.minutes) do |req|
  req.ip if req.path == "/oauth/token" && req.post?
end

# MCP calls are limited per access token for the same reason; requests without
# one count against their IP.
Rack::Attack.throttle("mcp/token", limit: 120, period: 1.minute) do |req|
  next unless req.path == "/mcp"

  bearer = req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (\S+)\z/i, 1]
  bearer ? Digest::SHA256.hexdigest(bearer) : req.ip
end

Rack::Attack.throttle("mcp/ip", limit: 1200, period: 1.minute) do |req|
  req.ip if req.path == "/mcp"
end

Rack::Attack.throttled_responder = ->(request) do
  retry_after = (request.env["rack.attack.match_data"] || {})[:period].to_i
  [429, {"Content-Type" => "application/json", "Retry-After" => retry_after.to_s}, [{error: "Too many requests"}.to_json]]
end
