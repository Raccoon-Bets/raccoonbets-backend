# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP authorization" do
  let(:user) { create(:user) }
  let(:membership) { create(:membership, user:) }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:resource) { "#{Rails.application.config.urls.backend}/mcp" }
  let(:redirect_uri) { "https://assistant.example/callback" }

  before(:each) { allow(Mcp::Configuration).to receive(:enabled?).and_return(true) }

  def register_client(redirect_uris: [redirect_uri])
    post "/oauth/register", params: {
        client_name:                "Test assistant",
        redirect_uris:,
        token_endpoint_auth_method: "none"
    }, as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body.fetch("client_id")
  end

  def begin_authorization(client_id, **overrides)
    get "/oauth/authorize", params: {
        client_id:,
        redirect_uri:,
        response_type:         "code",
        scope:                 "mcp:read mcp:write",
        resource:,
        code_challenge:        Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
        code_challenge_method: "S256",
        state:                 "client-state",
        **overrides
    }.compact
  end

  def pending_request_id = URI(response.location).path.split("/").last

  def client_error
    expect(response).to have_http_status(:found)
    URI.decode_www_form(URI(response.location).query).to_h.values_at("error", "state")
  end

  def consent_to(client_id)
    begin_authorization(client_id)
    expect(response).to have_http_status(:found)
    sign_in user
    post "/oauth/requests/#{pending_request_id}/decision", params: {
        approve: true, group_ids: [membership.group_id], write: true
    }, as: :json
    expect(response).to be_successful
    query = URI.decode_www_form(URI(response.parsed_body.fetch("redirect_uri")).query).to_h
    expect(query.fetch("state")).to eq("client-state")
    sign_out
    query.fetch("code")
  end

  def exchange(client_id, code, **overrides)
    post "/oauth/token", params: {
        grant_type:    "authorization_code",
        client_id:,
        code:,
        redirect_uri:,
        code_verifier: verifier,
        resource:,
        **overrides
    }
  end

  def refresh(client_id, refresh_token, **)
    post "/oauth/token", params: {grant_type: "refresh_token", client_id:, refresh_token:, **}
  end

  def listed_connections
    sign_in user
    get "/account/mcp_connections", as: :json
    sign_out
    expect(response.parsed_body).to include("server_url" => resource)
    response.parsed_body.fetch("connections")
  end

  it "binds tokens to selected groups, lists the connection once established, and revokes it" do
    client_id = register_client
    code = consent_to(client_id)
    expect(listed_connections).to be_empty

    exchange(client_id, code, resource: "#{resource}/")
    expect(response).to be_successful
    tokens = response.parsed_body
    connection = Oauth::AccessToken.by_token(tokens.fetch("access_token")).mcp_connection
    expect(connection.groups).to contain_exactly(membership.group)
    expect(listed_connections).to match([include("id" => connection.id, "client_name" => "Test assistant",
                                                 "scopes" => %w[mcp:read mcp:write])])

    refresh(client_id, tokens.fetch("refresh_token"))
    expect(response).to be_successful
    refreshed = response.parsed_body.fetch("refresh_token")

    sign_in user
    delete "/account/mcp_connections/#{connection.id}"
    expect(response).to have_http_status(:no_content)
    expect(listed_connections).to be_empty
    refresh(client_id, refreshed)
    expect(response).to have_http_status(:bad_request)
  end

  it "tolerates a concurrent refresh but revokes the connection when a rotated token is replayed later" do
    client_id = register_client
    exchange(client_id, consent_to(client_id))
    original = response.parsed_body.fetch("refresh_token")
    refresh(client_id, original)
    current = response.parsed_body.fetch("refresh_token")
    refresh(client_id, original)
    expect(response).to have_http_status(:bad_request)
    refresh(client_id, current)
    expect(response).to be_successful
    latest = response.parsed_body.fetch("refresh_token")

    travel 1.minute do
      refresh(client_id, current)
      expect(response).to have_http_status(:bad_request)
      refresh(client_id, latest)
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "revokes the connection when the client revokes its refresh token" do
    client_id = register_client
    exchange(client_id, consent_to(client_id))
    refresh_token = response.parsed_body.fetch("refresh_token")

    post "/oauth/revoke", params: {client_id:, token: refresh_token, token_type_hint: "refresh_token"}
    expect(response).to be_successful
    expect(listed_connections).to be_empty
  end

  it "refuses an unknown client or redirect URI outright and reports other errors to the client" do
    client_id = register_client
    begin_authorization("unknown")
    expect(response).to have_http_status(:bad_request)
    begin_authorization(client_id, redirect_uri: "https://attacker.example/callback")
    expect(response).to have_http_status(:bad_request)
    expect(response.headers["Location"]).to be_nil

    begin_authorization(client_id, code_challenge: nil)
    expect(client_error).to eq(%w[invalid_request client-state])
    begin_authorization(client_id, resource: "https://other.example/mcp")
    expect(client_error).to eq(%w[invalid_target client-state])
  end

  it "defaults an omitted resource and accepts it with a trailing slash" do
    client_id = register_client
    [nil, "#{resource}/"].each do |indicator|
      begin_authorization(client_id, resource: indicator)
      expect(response.location).to start_with("#{Rails.application.config.urls.frontend}/oauth/consent/")
      expect(McpAuthorizationRequest.find_by!(identifier: pending_request_id).parameters).
          to include("resource" => resource)
    end
  end

  it "registers loopback redirects for native clients and matches them on any port" do
    post "/oauth/register", params: {client_name: "CLI", redirect_uris: ["http://example.com/callback"]}, as: :json
    expect(response).to have_http_status(:bad_request)

    {
        "http://localhost:1234/callback" => "http://localhost:53123/callback",
        "http://127.0.0.1/callback"      => "http://127.0.0.1:53123/callback",
        "http://[::1]:80/callback"       => "http://[::1]:53123/callback"
    }.each do |registered, requested|
      begin_authorization(register_client(redirect_uris: [registered]), redirect_uri: requested)
      expect(response.location).to start_with("#{Rails.application.config.urls.frontend}/oauth/consent/")
    end
  end

  it "does not exchange a code for another resource" do
    client_id = register_client
    exchange(client_id, consent_to(client_id), resource: "https://other.example/mcp")
    expect(response).to have_http_status(:bad_request)
  end

  describe "deciding a consent request" do
    let(:client_id) { register_client }
    let(:request_id) do
      begin_authorization(client_id)
      pending_request_id
    end

    def decide(group_ids: [membership.group_id], id: request_id)
      post "/oauth/requests/#{id}/decision", params: {approve: true, group_ids:}, as: :json
    end

    it "requires a website login" do
      decide
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses groups the member does not belong to" do
      sign_in user
      decide(group_ids: [create(:group).id])
      expect(response).to have_http_status(:bad_request)
      expect(McpConnection.count).to eq(0)
    end

    it "consumes the request once" do
      sign_in user
      decide
      expect(response).to be_successful
      decide
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "request_unavailable")
    end

    it "refuses unknown and expired requests" do
      sign_in user
      get "/oauth/requests/unknown"
      expect(response.parsed_body).to eq("error" => "request_unavailable")
      request_id
      travel 11.minutes do
        decide
        expect(response).to have_http_status(:not_found)
      end
    end

    it "refuses members whose account is not open" do
      user.update!(status_id: User::CLOSED_STATUS)
      sign_in user
      get "/oauth/requests/#{request_id}"
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("error" => "account_unavailable")
    end
  end

  it "returns cancellation without issuing credentials and binds displayed consent to its viewer" do
    client_id = register_client
    begin_authorization(client_id)
    request_id = pending_request_id
    sign_in user
    get "/oauth/requests/#{request_id}"
    expect(response.parsed_body).to include("client_name" => "Test assistant", "lifetime_days" => 30,
                                            "account"     => {"name" => user.name, "email" => user.email})
    sign_in create(:user)
    post "/oauth/requests/#{request_id}/decision", params: {approve: false}, as: :json
    expect(response.parsed_body).to eq("error" => "request_unavailable")
    sign_in user
    post "/oauth/requests/#{request_id}/decision", params: {approve: false}, as: :json
    expect(response.parsed_body.fetch("redirect_uri")).to include("error=access_denied", "state=client-state")
    expect(McpConnection.count).to eq(0)
  end

  it "does not extend a connection's lifetime on refresh" do
    client_id = register_client
    exchange(client_id, consent_to(client_id))
    refresh_token = response.parsed_body.fetch("refresh_token")
    travel 31.days do
      refresh(client_id, refresh_token, resource:)
      expect(response).to have_http_status(:bad_request)
    end
  end
end
