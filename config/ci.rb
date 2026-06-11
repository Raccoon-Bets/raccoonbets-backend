# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  # RuboCop lives in the RVM @global gemset, so run it outside the bundle.
  Bundler.with_unbundled_env do
    step "Style: RuboCop", "rubocop --parallel"
  end

  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Tests: RSpec", "bundle exec rspec"
end
