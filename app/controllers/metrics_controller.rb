# frozen_string_literal: true

# Exposes Prometheus metrics for Fly.io scraping.

class MetricsController < ActionController::API
  def show
    Yabeda.collectors.each(&:call)

    # Uncompressed, because only the content type is copied onto the response:
    # a gzipped body would reach the scraper without its Content-Encoding.
    _, headers, body = Yabeda::Prometheus::Exporter.rack_app(use_deflater: false).call(request.env)
    response_body = []
    body.each { |chunk| response_body << chunk } # rubocop:disable Style/MapIntoArray
    body.close if body.respond_to?(:close)

    render plain:        response_body.join,
           content_type: headers["content-type"] || "text/plain; version=0.0.4; charset=utf-8"
  end
end
