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

Rails.application.config.middleware.insert_before 0, Rack::Cors do
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
