# frozen_string_literal: true

# A single-use PKCE authorization code issued under one member connection.
#
# Associations
# ------------
#
# |                  |                                                  |
# |:-----------------|:-------------------------------------------------|
# | `mcp_connection` | The {McpConnection} the code was approved under. |

class Oauth::AccessGrant < ApplicationRecord
  include Doorkeeper::Orm::ActiveRecord::Mixins::AccessGrant

  self.table_name = "oauth_access_grants"
  belongs_to :mcp_connection
end
