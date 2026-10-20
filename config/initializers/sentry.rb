# frozen_string_literal: true

Sentry.init do |config|
  config.breadcrumbs_logger = %i[active_support_logger http_logger]
  config.dsn                = ENV.fetch("SENTRY_DSN", nil)

  config.send_default_pii = true

  # OAuth credentials and assistant arguments stay out of error and performance events.
  filter_assistant_request = ->(event, _hint) do
    if event.request&.url&.match?(%r{\Ahttps?://[^/]+/(?:mcp(?:/|\z)|oauth/)})
      event.request.data = nil
    end
    event
  end
  config.before_send = filter_assistant_request
  config.before_send_transaction = filter_assistant_request

  config.enabled_patches = %i[logger]

  config.traces_sample_rate = 1.0
  config.profiles_sample_rate = 1.0
  config.profiler_class = Sentry::Vernier::Profiler
end
