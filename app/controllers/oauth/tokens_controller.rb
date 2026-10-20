# frozen_string_literal: true

# Applies resource and connection restrictions before Doorkeeper exchanges credentials.
class Oauth::TokensController < Doorkeeper::TokensController
  prepend_before_action :require_mcp_enabled!

  # Exchanges a code or refresh credential only while its bound consent is valid.
  def create
    validate_connection!
    super unless performed?
  end

  private

  def require_mcp_enabled!
    head :not_found unless Mcp::Configuration.enabled?
  end

  def validate_connection!
    credential = case params[:grant_type]
                   when "authorization_code" then Oauth::AccessGrant.by_token(params[:code])
                   when "refresh_token" then Oauth::AccessToken.by_refresh_token(params[:refresh_token])
                 end
    connection = credential&.mcp_connection
    return if connection&.active? && params[:resource] == connection.resource

    response.headers["Cache-Control"] = "no-store"
    render json: {error: "invalid_grant"}, status: :bad_request
  end

  def authorized?
    server.client && token && server.client.application.id == token.application_id
  end
end
