# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require_relative "../../app/middleware/verify_database_connection"
require_relative "../../app/middleware/verify_redis_connection"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = {"cache-control" => "public, max-age=#{1.year.to_i}"}

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = %i[request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  config.action_mailer.delivery_method     = :resend
  config.action_mailer.perform_deliveries  = true
  config.action_mailer.default_url_options = {host: Rails.application.config.urls.frontend}

  # Background jobs run on Sidekiq (Redis-backed) so Postgres can scale to zero.
  config.active_job.queue_adapter = :sidekiq

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = %i[id]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # Group subdomains are served by the frontend app; the API only ever
  # answers on its own host.
  config.hosts = %w[raccoonbets.org api.raccoonbets.org]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Reconnect to Redis (rack-attack) and Postgres if pooled sockets died
  # during Fly suspend. Order matters: Rack::Attack runs early in the stack
  # and trips Redis before any controller touches AR, so verify Redis first.
  config.middleware.use VerifyRedisConnection
  config.middleware.use VerifyDatabaseConnection
end
