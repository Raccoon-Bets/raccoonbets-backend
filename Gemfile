# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "4.0.5"

# CORE
gem "bootsnap", require: false
gem "puma"
gem "rails"
gem "responders"

# FRAMEWORK
gem "anycable-rails"
gem "bcrypt"
gem "jwt"
gem "kredis"
gem "omniauth-apple"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "rack-attack"
gem "rack-cors"
gem "redis"
gem "rodauth-omniauth"
gem "rodauth-rails"
gem "sequel-activerecord_connection"
gem "tilt"
gem "webauthn"

# MODELS
gem "money"
gem "pg"

# VIEWS
gem "alba"
gem "oj"

# MAIL
gem "resend"

# JOBS
gem "solid_queue"

# PUSH
gem "web-push"

# ERRORS
gem "sentry-rails"
gem "sentry-ruby"
gem "vernier"

# METRICS (production only - excluded from test/CI)
gem "yabeda", group: %i[development production]
gem "yabeda-prometheus", group: %i[development production]
gem "yabeda-puma-plugin", group: %i[development production]
gem "yabeda-rails", group: %i[development production]

group :development, :test do
  gem "debug", require: "debug/prelude"
end

group :development do
  # LINT
  gem "brakeman", require: false

  # MAIL
  gem "letter_opener"

  # ERRORS
  gem "binding_of_caller"

  # FLY.IO
  gem "dockerfile-rails"
end

group :doc do
  gem "redcarpet", require: false
  gem "yard", require: false
end

group :test do
  # SPECS
  gem "rails-controller-testing"
  gem "rspec-rails"

  # FACTORIES
  gem "factory_bot_rails"
  gem "faker"

  # ISOLATION
  gem "database_cleaner-active_record"
  gem "webmock"
end
