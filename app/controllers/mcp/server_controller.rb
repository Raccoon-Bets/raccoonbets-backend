# frozen_string_literal: true

# The member MCP server's stateless Streamable HTTP transport. Each request
# presents an OAuth access token issued under an active {McpConnection} and
# gets a fresh server whose tools act as that connection's member
# ({Mcp::ToolContext}). Read-only connections are offered only the read tools.
# A missing or unusable token renders 401 with an RFC 6750 challenge pointing
# at the protected-resource metadata.

class Mcp::ServerController < ActionController::API
  before_action :authenticate_connection!

  # Handles one JSON-RPC request through the official MCP SDK.
  #
  # Routes
  # ------
  #
  # * `GET /mcp`
  # * `POST /mcp`
  # * `DELETE /mcp`

  def handle
    context = Mcp::ToolContext.new(@token)
    server = MCP::Server.new(name: "raccoon_bets", version: "1.0.0", tools: Mcp::Tools.available(writable: context.writable?),
                             server_context: context,
                             configuration: MCP::Configuration.new(exception_reporter: ->(error, _) { Sentry.capture_exception(error) }))
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server, stateless: true, serve_subscriptions_listen: false,
      allowed_hosts: [URI(Mcp::Configuration.issuer).host],
      allowed_origins: [Rails.application.config.urls.frontend, *Rails.application.config.x.mcp_assistant_origins]
    )
    status, headers, body = transport.handle_request(request)
    response.status = status
    headers.each { |key, value| response.headers[key] = value }
    self.response_body = body
  rescue StandardError => e
    Sentry.capture_exception(e)
    render json: {error: "An internal error occurred"}, status: :internal_server_error
  end

  private

  def authenticate_connection!
    return head :not_found unless Mcp::Configuration.enabled?

    response.headers["Cache-Control"] = "no-store"
    bearer = request.authorization.to_s.match(/\ABearer ([^\s]+)\z/i)&.captures&.first
    @token = Oauth::AccessToken.by_token(bearer) if bearer
    return if @token&.acceptable?("mcp:read") && @token.mcp_connection.active?

    response.headers["WWW-Authenticate"] = bearer_challenge(token_presented: bearer.present?)
    render json: {error: "unauthorized"}, status: :unauthorized
  end

  # Builds an RFC 6750 challenge, flagging a presented token as invalid.
  def bearer_challenge(token_presented:)
    attributes = {resource_metadata: "#{Mcp::Configuration.issuer}/.well-known/oauth-protected-resource/mcp",
                  scope:             Mcp::Configuration::SCOPES.join(" ")}
    attributes[:error] = "invalid_token" if token_presented
    "Bearer #{attributes.map { |name, value| %(#{name}="#{value}") }.join(", ")}"
  end
end
