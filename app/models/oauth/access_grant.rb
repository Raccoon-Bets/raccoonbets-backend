# frozen_string_literal: true

# Single-use PKCE authorization code bound to the approved connection.
class Oauth::AccessGrant < ApplicationRecord
  include Doorkeeper::Orm::ActiveRecord::Mixins::AccessGrant

  self.table_name = "oauth_access_grants"
  belongs_to :mcp_connection
end
