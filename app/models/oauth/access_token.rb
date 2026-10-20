# frozen_string_literal: true

# OAuth access and refresh credentials belonging to one member connection.
# Issuing the first one marks the {McpConnection} as established.

class Oauth::AccessToken < ApplicationRecord
  include Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken

  self.table_name = "oauth_access_tokens"
  belongs_to :mcp_connection

  after_create { mcp_connection.establish! }

  # Rotates refresh credentials immediately, including concurrent exchanges.
  def self.refresh_token_revoked_on_use? = false
end
