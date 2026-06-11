# frozen_string_literal: true

require "net/http"
require "json"

class TurnstileVerifier
  Result = Struct.new(:success?, :error_codes, keyword_init: true)
  ENDPOINT = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  def self.verify(token, remote_ip)
    secret = ENV.fetch("TURNSTILE_SECRET_KEY") do
      raise "TURNSTILE_SECRET_KEY missing" unless Rails.env.local? || Rails.env.cypress?

      "1x0000000000000000000000000000000AA" # Cloudflare always-passes test secret
    end
    return Result.new(success?: false, error_codes: %w[missing-input-response]) if token.blank?

    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10
    req = Net::HTTP::Post.new(ENDPOINT.path)
    req.set_form_data(secret: secret, response: token, remoteip: remote_ip.to_s)
    res = http.request(req)
    data = JSON.parse(res.body)
    Result.new(success?: data["success"] == true, error_codes: data["error-codes"] || [])
  rescue StandardError => e
    Sentry.add_breadcrumb(Sentry::Breadcrumb.new(category: "turnstile", message: e.message)) if defined?(Sentry)
    Result.new(success?: false, error_codes: %w[network-error])
  end
end
