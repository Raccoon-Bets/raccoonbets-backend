# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP tools" do
  let(:member) { create(:membership) }
  let(:group) { member.group }
  let(:application) { Doorkeeper::Application.create!(name: "Assistant", redirect_uri: "https://assistant.example/callback", confidential: false) }
  let(:scopes) { "mcp:read mcp:write" }
  let(:connection) do
    McpConnection.create!(user: member.user, application:, groups: [group], scopes:,
                          resource: Mcp::Configuration.resource, expires_at: 30.days.from_now)
  end
  let(:token) do
    Oauth::AccessToken.create!(application:, resource_owner_id: member.user_id, mcp_connection: connection,
                               scopes: connection.scopes, expires_in: 900)
  end
  let(:headers) do
    {"Authorization" => "Bearer #{token.plaintext_token}", "Accept" => "application/json, text/event-stream"}
  end
  let(:market) { create(:market, group:) }
  let(:bet) { {group_id: group.subdomain, market_id: market.id, outcome_id: market.outcomes.first.id, amount_cents: 200} }

  before(:each) do
    allow(Mcp::Configuration).to receive(:enabled?).and_return(true)
    host! URI(Mcp::Configuration.issuer).host
  end

  def rpc(method, params={}, headers: self.headers)
    post "/mcp", headers:, params: {jsonrpc: "2.0", id: 1, method:, params:}, as: :json
  end

  def tool_names
    rpc("tools/list")
    expect(response).to be_successful, "#{response.status}: #{response.body}"
    response.parsed_body.dig("result", "tools").pluck("name")
  end

  def call_tool(name, arguments={})
    rpc("tools/call", {name:, arguments:})
    expect(response).to be_successful, "#{response.status}: #{response.body}"
    response.parsed_body.fetch("result")
  end

  def tool_error?(name, arguments={}) = call_tool(name, arguments).fetch("isError")

  it "discovers tools and returns only groups covered by consent" do
    create(:membership, user: member.user)
    rpc("initialize", {protocolVersion: "2025-03-26", capabilities: {}, clientInfo: {name: "test", version: "1"}})
    expect(response).to be_successful, "#{response.status}: #{response.body}"
    expect(tool_names).to include("list_groups", "set_position", "record_settlement")
    expect(call_tool("list_groups").dig("structuredContent", "data").pluck("subdomain")).to eq([group.subdomain])
  end

  it "places the caller's bet, and rejects another group's market" do
    expect(tool_error?("set_position", bet)).to be(false)
    expect(member.positions.find_by!(market:).amount_cents).to eq(200)
    other = create(:market)
    expect(tool_error?("set_position", bet.merge(market_id: other.id))).to be(true)
    expect(other.positions).to be_empty
  end

  context "with a read-only connection" do
    let(:scopes) { "mcp:read" }

    it "offers only the read tools and refuses write calls as read-only" do
      expect(tool_names).to include("list_groups", "get_market")
      expect(tool_names).not_to include("set_position", "record_settlement")
      expect(call_tool("set_position", bet)).to include("isError" => true)
      expect(response.body).to include("This connection has read-only access.")
      expect(member.positions).to be_empty
    end
  end

  it "stops serving a member who leaves the group" do
    member.update!(status: :requested)
    expect(tool_error?("get_market", {group_id: group.subdomain, market_id: market.id})).to be(true)
  end

  it "rejects revoked connections and website tokens, and keeps MCP tokens out of the REST API" do
    tool_names
    connection.revoke!
    rpc("tools/list")
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("oauth-protected-resource/mcp", 'error="invalid_token"',
                                                            'scope="mcp:read mcp:write"')
    get("/groups", headers:)
    expect(response).to have_http_status(:bad_request)
    sign_in member.user
    rpc("tools/list", headers: {})
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses suspended groups and closed accounts" do
    group.update!(status: :suspended)
    expect(tool_error?("get_group", {group_id: group.subdomain})).to be(true)
    member.user.update!(status_id: User::CLOSED_STATUS)
    rpc("tools/list")
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses foreign origins and requests while the feature is off" do
    rpc("tools/list", headers: headers.merge("Origin" => "https://attacker.example"))
    expect(response).to have_http_status(:forbidden)
    allow(Mcp::Configuration).to receive(:enabled?).and_return(false)
    rpc("tools/list")
    expect(response).to have_http_status(:not_found)
  end

  it "rejects undeclared arguments and returns business errors without changing positions" do
    locked = create(:market, :locked, group:)
    result = call_tool("set_position", bet.merge(market_id: locked.id, outcome_id: locked.outcomes.first.id))
    expect(result.fetch("isError")).to be(true)
    expect(result.dig("structuredContent", "errors", "base")).to include("trading is closed for this market")
    expect(tool_error?("set_position", bet.merge(membership_id: market.creator_id))).to be(true)
    expect(Position.where(market: [market, locked])).to be_empty
  end
end
