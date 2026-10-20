# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

# Every group lives on its own subdomain of raccoonbets.org (lvh.me in
# development), so the API must accept requests from the apex and any
# subdomain of the frontend host.
allowed_origins =
    if Rails.env.production?
      [%r{\Ahttps://([a-z0-9-]+\.)?raccoonbets\.org\z}]
    elsif Rails.env.development? || Rails.env.cypress?
      [Rails.application.config.urls.frontend, %r{\Ahttp://([a-z0-9-]+\.)?lvh\.me:(5173|4173)\z}]
    else
      [Rails.application.config.urls.frontend]
    end

# Shared with the OmniAuth callback (app/misc/rodauth_app.rb), which validates
# the origin it redirects the browser back to against this same trusted set.
Rails.application.config.x.frontend_origin_patterns = allowed_origins

# Hosted assistants whose browser clients call the MCP endpoint directly.
# Shared with the MCP transport's origin check (Mcp::ServerController).
Rails.application.config.x.mcp_assistant_origins = %w[https://chatgpt.com https://claude.ai].freeze

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/.well-known/*", headers: :any, methods: %i[get options]
    %w[/oauth/register /oauth/token /oauth/revoke].each do |path|
      resource path, headers: %w[Authorization Content-Type], methods: %i[post options]
    end
  end
  allow do
    origins Rails.application.config.urls.frontend, *Rails.application.config.x.mcp_assistant_origins
    resource "/mcp", headers: %w[Authorization Content-Type MCP-Protocol-Version MCP-Session-Id],
                     methods: %i[get post delete options], expose: %w[WWW-Authenticate MCP-Session-Id]
  end
  allow do
    origins(*allowed_origins)
    resource "*",
             headers:     %w[Authorization X-Locale],
             methods:     :any,
             expose:      %w[Authorization],
             max_age:     600,
             credentials: true
  end
end
