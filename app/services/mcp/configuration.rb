# frozen_string_literal: true

# Deployment settings for the member MCP endpoint and its OAuth resource.
module Mcp::Configuration
  # @return [Boolean] whether new authorizations and MCP requests are enabled.
  def self.enabled? = ENV.fetch("MCP_ENABLED", Rails.env.cypress? ? "true" : "false") == "true"

  # @return [String] the configured API origin, never inferred from request headers.
  def self.issuer = Rails.application.config.urls.backend.delete_suffix("/")

  # @return [String] the audience shared by MCP grants and discovery metadata.
  def self.resource = "#{issuer}/mcp"
end
