# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::CleanupJob do
  def register_client(created_at: 8.days.ago)
    Doorkeeper::Application.create!(name: "Assistant", redirect_uri: "https://assistant.example/callback",
                                    confidential: false, created_at:)
  end

  def request_authorization(client, expires_at: 5.minutes.from_now)
    McpAuthorizationRequest.create!(identifier: SecureRandom.hex, parameters: {client_id: client.uid}, expires_at:)
  end

  it "deletes expired authorization requests and old clients nobody connected" do
    unused      = register_client
    recent      = register_client(created_at: 1.day.ago)
    in_progress = register_client
    connected   = register_client
    McpConnection.create!(user: create(:user), application: connected, scopes: "mcp:read",
                          resource: Mcp::Configuration.resource, expires_at: 30.days.from_now)
    live = request_authorization(in_progress)
    request_authorization(unused, expires_at: 1.minute.ago)

    described_class.perform_now

    expect(Doorkeeper::Application.all).to contain_exactly(recent, in_progress, connected)
    expect(McpAuthorizationRequest.all).to contain_exactly(live)
  end
end
