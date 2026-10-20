# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP authorization" do
  let(:user) { create(:user) }
  let(:membership) { create(:membership, user:) }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:resource) { "#{Rails.application.config.urls.backend}/mcp" }
  let(:redirect_uri) { "https://assistant.example/callback" }

  before(:each) { allow(Mcp::Configuration).to receive(:enabled?).and_return(true) }

  def register_client
    post "/oauth/register", params: {
        client_name: "Test assistant", redirect_uris: [redirect_uri], token_endpoint_auth_method: "none"
    }, as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body.fetch("client_id")
  end

  def begin_authorization(client_id, **overrides)
    get "/oauth/authorize", params: {
        client_id:, redirect_uri:, response_type: "code", scope: "mcp:read mcp:write", resource:,
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      code_challenge_method: "S256", state: "client-state", **overrides
    }
  end

  def consent_to(client_id)
    begin_authorization(client_id)
    expect(response).to have_http_status(:found)
    request_id = URI(response.location).path.split("/").last
    sign_in user
    post "/oauth/requests/#{request_id}/decision", params: {
        approve: true, group_ids: [membership.group_id], write: true
    }, as: :json
    expect(response).to be_successful
    query = URI.decode_www_form(URI(response.parsed_body.fetch("redirect_uri")).query).to_h
    expect(query.fetch("state")).to eq("client-state")
    @_auth_headers = nil
    query.fetch("code")
  end

  def exchange(client_id, code, **overrides)
    post "/oauth/token", params: {
        grant_type: "authorization_code", client_id:, code:, redirect_uri:, code_verifier: verifier,
      resource:, **overrides
    }
  end

  it "binds tokens to selected groups, rotates refresh tokens, and revokes the connection" do
    client_id = register_client
    code = consent_to(client_id)
    exchange(client_id, code)
    expect(response).to be_successful
    tokens = response.parsed_body
    token = Oauth::AccessToken.by_token(tokens.fetch("access_token"))
    expect(token.mcp_connection.groups).to contain_exactly(membership.group)
    expect(token.token).not_to eq(tokens.fetch("access_token"))

    post "/oauth/token", params: {grant_type: "refresh_token", client_id:, resource:,
                                  refresh_token: tokens.fetch("refresh_token")}
    expect(response).to be_successful
    refreshed = response.parsed_body
    expect(refreshed.fetch("refresh_token")).not_to eq(tokens.fetch("refresh_token"))

    post "/oauth/token", params: {grant_type: "refresh_token", client_id:, resource:,
                                  refresh_token: tokens.fetch("refresh_token")}
    expect(response).to have_http_status(:bad_request)

    sign_in user
    delete "/account/mcp_connections/#{token.mcp_connection_id}"
    expect(response).to have_http_status(:no_content)
    @_auth_headers = nil
    post "/oauth/token", params: {grant_type: "refresh_token", client_id:, resource:,
                                  refresh_token: refreshed.fetch("refresh_token")}
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects mismatched redirect URIs and missing PKCE before redirecting" do
    client_id = register_client
    begin_authorization(client_id, redirect_uri: "https://attacker.example/callback")
    expect(response).to have_http_status(:bad_request)
    expect(response.headers["Location"]).to be_nil
    begin_authorization(client_id, code_challenge: nil)
    expect(response).to have_http_status(:bad_request)
  end

  it "does not exchange a code with the wrong verifier or resource" do
    client_id = register_client
    code = consent_to(client_id)
    exchange(client_id, code, code_verifier: "wrong")
    expect(response).to have_http_status(:bad_request)
    exchange(client_id, code, resource: "https://other.example/mcp")
    expect(response).to have_http_status(:bad_request)
  end

  it "requires a website login and refuses unowned groups, expired requests, and replayed consent" do
    client_id = register_client
    begin_authorization(client_id)
    request_id = URI(response.location).path.split("/").last
    path = "/oauth/requests/#{request_id}/decision"
    post path, params: {approve: true, group_ids: [membership.group_id]}, as: :json
    expect(response).to have_http_status(:unauthorized)
    sign_in user
    post path, params: {approve: true, group_ids: [create(:group).id]}, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(McpConnection.count).to eq(0)
    post path, params: {approve: true, group_ids: [membership.group_id]}, as: :json
    expect(response).to be_successful
    post path, params: {approve: true, group_ids: [membership.group_id]}, as: :json
    expect(response).to have_http_status(:not_found)
    begin_authorization(client_id)
    request_id = URI(response.location).path.split("/").last
    travel 11.minutes do
      post "/oauth/requests/#{request_id}/decision", params: {approve: true, group_ids: [membership.group_id]}, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  it "returns cancellation without issuing credentials and binds displayed consent to its viewer" do
    client_id = register_client
    begin_authorization(client_id)
    request_id = URI(response.location).path.split("/").last
    sign_in user
    get "/oauth/requests/#{request_id}"
    expect(response).to be_successful
    sign_in create(:user)
    post "/oauth/requests/#{request_id}/decision", params: {approve: false}, as: :json
    expect(response).to have_http_status(:not_found)
    sign_in user
    post "/oauth/requests/#{request_id}/decision", params: {approve: false}, as: :json
    expect(response.parsed_body.fetch("redirect_uri")).to include("error=access_denied", "state=client-state")
    expect(McpConnection.count).to eq(0)
  end

  it "does not extend a connection's lifetime or broaden a grant on refresh" do
    client_id = register_client
    code = consent_to(client_id)
    exchange(client_id, code)
    refresh_token = response.parsed_body.fetch("refresh_token")
    post "/oauth/token", params: {grant_type: "refresh_token", client_id:, resource:, refresh_token:, scope: "admin"}
    expect(response).to have_http_status(:bad_request)
    travel 31.days do
      post "/oauth/token", params: {grant_type: "refresh_token", client_id:, resource:, refresh_token:}
      expect(response).to have_http_status(:bad_request)
    end
  end
end
