# frozen_string_literal: true

# Stateless HTTP MCP transport with a fresh identity and server for each request.
class Mcp::ServerController < ActionController::API
  before_action :authenticate_connection!

  # Dispatches protocol requests through the official SDK.
  def handle
    server = MCP::Server.new(name: "raccoon_bets", version: "1.0.0", tools: Mcp::Tools.all,
                             server_context: Mcp::ToolContext.new(@token),
                             configuration: MCP::Configuration.new(exception_reporter: ->(error, _) { Sentry.capture_exception(error) }))
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server, stateless: true, serve_subscriptions_listen: false,
      allowed_hosts: [URI(Mcp::Configuration.issuer).host],
      allowed_origins: [Rails.application.config.urls.frontend, "https://chatgpt.com", "https://claude.ai"]
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

    response.headers["WWW-Authenticate"] = %(Bearer resource_metadata="#{Mcp::Configuration.issuer}/.well-known/oauth-protected-resource/mcp")
    render json: {error: "unauthorized"}, status: :unauthorized
  end
end
