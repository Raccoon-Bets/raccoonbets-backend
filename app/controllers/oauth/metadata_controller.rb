# frozen_string_literal: true

# Publishes OAuth and protected-resource discovery without requiring a login.

class Oauth::MetadataController < Oauth::BaseController
  # Returns authorization-server endpoints and supported grant parameters
  # (RFC 8414).
  #
  # Routes
  # ------
  #
  # * `GET /.well-known/oauth-authorization-server`

  def show
    issuer = Mcp::Configuration.issuer
    render json: {
        issuer:,
        authorization_endpoint:                "#{issuer}/oauth/authorize",
        token_endpoint:                        "#{issuer}/oauth/token",
        registration_endpoint:                 "#{issuer}/oauth/register",
        revocation_endpoint:                   "#{issuer}/oauth/revoke",
        response_types_supported:              %w[code],
        grant_types_supported:                 Mcp::Configuration::GRANT_TYPES,
        code_challenge_methods_supported:      %w[S256],
        token_endpoint_auth_methods_supported: %w[none],
        scopes_supported:                      Mcp::Configuration::SCOPES
    }
  end

  # Returns the canonical MCP resource and its authorization server
  # (RFC 9728).
  #
  # Routes
  # ------
  #
  # * `GET /.well-known/oauth-protected-resource`
  # * `GET /.well-known/oauth-protected-resource/mcp`

  def resource
    render json: {
        resource:                 Mcp::Configuration.resource,
        authorization_servers:    [Mcp::Configuration.issuer],
        scopes_supported:         Mcp::Configuration::SCOPES,
        bearer_methods_supported: %w[header]
    }
  end
end
