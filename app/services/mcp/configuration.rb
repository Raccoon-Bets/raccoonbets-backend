# frozen_string_literal: true

# Deployment settings for the member MCP endpoint and its OAuth resource.

module Mcp::Configuration
  # Scopes a member can grant: read access, plus optional write access.
  SCOPES = %w[mcp:read mcp:write].freeze

  # Grant types a registered MCP client may use at the token endpoint.
  GRANT_TYPES = %w[authorization_code refresh_token].freeze

  # @return [Boolean] Whether new authorizations and MCP requests are enabled.

  def self.enabled? = ENV.fetch("MCP_ENABLED", Rails.env.cypress? ? "true" : "false") == "true"

  # @return [String] The configured API origin, never inferred from request headers.

  def self.issuer = Rails.application.config.urls.backend.delete_suffix("/")

  # @return [String] The audience shared by MCP grants and discovery metadata.

  def self.resource = "#{issuer}/mcp"

  # @param indicator [String, nil] A client's RFC 8707 `resource` parameter.
  # @return [Boolean] Whether the indicator is absent or names {.resource},
  #   ignoring a trailing slash.

  def self.targets_resource?(indicator) = indicator.blank? || indicator.to_s.delete_suffix("/") == resource
end
