# frozen_string_literal: true

# Records when each MCP connection first issued an access token, so consents
# whose code was never redeemed can be told apart from working connections.
class AddEstablishedAtToMcpConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :mcp_connections, :established_at, :datetime

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE mcp_connections
          SET established_at = tokens.first_issued_at
          FROM (SELECT mcp_connection_id, MIN(created_at) AS first_issued_at
                FROM oauth_access_tokens GROUP BY mcp_connection_id) AS tokens
          WHERE tokens.mcp_connection_id = mcp_connections.id
        SQL
      end
    end
  end
end
