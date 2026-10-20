# frozen_string_literal: true

# An {McpConnection} as listed in the member's account settings. Never
# includes credentials.

class McpConnectionSerializer < ApplicationSerializer
  attributes :id, :expires_at

  attribute(:client_name) { it.application.name }
  attribute(:scopes) { it.scopes.split }
  attribute(:groups) { it.groups.as_json(only: %i[id name]) }
end
