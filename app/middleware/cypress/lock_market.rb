# frozen_string_literal: true

# Forces a Market's `locks_at` into the past so e2e tests can resolve it
# without waiting out a real countdown ("locked" is derived from `locks_at`).
# Responds with the market's ID.
#
# This middleware must be mounted at a specific route, not added to the
# middleware chain: `GET /__cypress__/lock_market?id=123`.

class Cypress::LockMarket
  def call(env)
    market = Market.find(Rack::Request.new(env).params.fetch("id"))
    # Validations would reject a past locks_at; bypass them — this shortcut
    # exists precisely to fabricate that state.
    market.update_columns locks_at: 1.minute.ago # rubocop:disable Rails/SkipsModelValidations
    [200, {"Content-Type" => "text/plain"}, [market.id.to_s]]
  end
end
