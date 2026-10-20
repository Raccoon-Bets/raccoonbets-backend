# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP tools" do
  let(:member) { create(:membership) }
  let(:group) { member.group }
  let(:application) { Doorkeeper::Application.create!(name: "Assistant", redirect_uri: "https://assistant.example/callback", confidential: false) }
  let(:connection) do
    McpConnection.create!(user: member.user, application:, groups: [group], scopes: "mcp:read mcp:write",
                          resource: Mcp::Configuration.resource, expires_at: 30.days.from_now)
  end
  let(:token) do
    Oauth::AccessToken.create!(application:, resource_owner_id: member.user_id, mcp_connection: connection,
                               scopes: connection.scopes, expires_in: 900)
  end
  let(:headers) do
    {"Authorization" => "Bearer #{token.plaintext_token}", "Accept" => "application/json, text/event-stream"}
  end

  before(:each) do
    allow(Mcp::Configuration).to receive(:enabled?).and_return(true)
    host! URI(Mcp::Configuration.issuer).host
  end

  def rpc(method, params={})
    post "/mcp", headers:, params: {jsonrpc: "2.0", id: 1, method:, params:}, as: :json
  end

  def call_tool(name, arguments={})
    rpc("tools/call", {name:, arguments:})
    expect(response).to be_successful, "#{response.status}: #{response.body}"
    response.parsed_body.fetch("result")
  end

  it "discovers tools and returns only groups covered by consent" do
    create(:membership, user: member.user)
    rpc("initialize", {protocolVersion: "2025-03-26", capabilities: {}, clientInfo: {name: "test", version: "1"}})
    expect(response).to be_successful, "#{response.status}: #{response.body}"
    rpc("tools/list")
    names = response.parsed_body.fetch("result").fetch("tools").pluck("name")
    expect(names).to include("list_groups", "set_position", "record_settlement")
    expect(names).not_to include("delete_market", "create_group")
    result = call_tool("list_groups")
    expect(result.dig("structuredContent", "data").pluck("subdomain")).to eq([group.subdomain])
  end

  it "places the caller's bet, and rejects another group's market" do
    market = create(:market, group:)
    args = {group_id: group.subdomain, market_id: market.id, outcome_id: market.outcomes.first.id, amount_cents: 200}
    expect(call_tool("set_position", args).fetch("isError")).to be(false)
    expect(member.positions.find_by!(market:).amount_cents).to eq(200)
    other = create(:market)
    expect(call_tool("set_position", args.merge(market_id: other.id)).fetch("isError")).to be(true)
    expect(other.positions).to be_empty
  end

  it "enforces read-only scope and current membership even with a previously issued token" do
    connection.update!(scopes: "mcp:read")
    market = create(:market, group:)
    args = {group_id: group.subdomain, market_id: market.id, outcome_id: market.outcomes.first.id, amount_cents: 200}
    expect(call_tool("set_position", args).fetch("isError")).to be(true)
    expect(member.positions).to be_empty
    member.update!(status: :requested)
    expect(call_tool("get_market", {group_id: group.subdomain, market_id: market.id}).fetch("isError")).to be(true)
  end

  it "rejects revoked connections and website tokens, and keeps MCP tokens out of the REST API" do
    rpc("tools/list")
    expect(response).to be_successful, "#{response.status}: #{response.body}"
    connection.revoke!
    rpc("tools/list")
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("oauth-protected-resource/mcp")
    get("/groups", headers:)
    expect(response).to have_http_status(:bad_request)
    sign_in member.user
    post "/mcp", params: {jsonrpc: "2.0", id: 1, method: "tools/list"}, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "enforces group suspension, closed accounts, the feature flag, and origin checks" do
    token
    group.update!(status: :suspended)
    expect(call_tool("get_group", {group_id: group.subdomain}).fetch("isError")).to be(true)
    member.user.update!(status_id: 3)
    rpc("tools/list")
    expect(response).to have_http_status(:unauthorized)
    member.user.update!(status_id: 2)
    post "/mcp", headers: headers.merge("Origin" => "https://attacker.example"),
                 params: {jsonrpc: "2.0", id: 1, method: "tools/list"}, as: :json
    expect(response).to have_http_status(:forbidden)
    allow(Mcp::Configuration).to receive(:enabled?).and_return(false)
    rpc("tools/list")
    expect(response).to have_http_status(:not_found)
  end

  it "rejects undeclared arguments and returns business errors without changing positions" do
    market = create(:market, :locked, group:)
    args = {group_id: group.subdomain, market_id: market.id, outcome_id: market.outcomes.first.id, amount_cents: 200}
    result = call_tool("set_position", args)
    expect(result.fetch("isError")).to be(true)
    expect(result.dig("structuredContent", "errors", "base")).to include("trading is closed for this market")
    rpc("tools/call", {name: "set_position", arguments: args.merge(membership_id: market.creator_id)})
    expect(response.parsed_body.dig("result", "isError")).to be(true)
    expect(market.positions).to be_empty
  end
end
