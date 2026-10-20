# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sentry::Configuration do
  def filtered_request(path, callback)
    event = Sentry::ErrorEvent.new(configuration: Sentry.configuration)
    event.rack_env = Rack::MockRequest.env_for("https://api.example#{path}", method: "POST", input: {
        params: {arguments: {body: "private comment"}}, code_verifier: "private verifier"
    }.to_json, "CONTENT_TYPE" => "application/json")
    Sentry.configuration.public_send(callback)&.call(event, {})
    event.to_h.fetch(:request)
  end

  it "excludes MCP and OAuth bodies from errors and performance events" do
    paths = %w[/mcp /oauth/token /oauth/requests/pending/decision]
    %i[before_send before_send_transaction].each do |callback|
      paths.each do |path|
        request = filtered_request(path, callback)
        expect(request[:data]).to be_nil
        expect(request[:url]).to eq("https://api.example#{path}")
      end
      expect(filtered_request("/groups", callback)[:data]).to include("params")
    end
  end
end
