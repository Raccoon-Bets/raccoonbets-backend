# frozen_string_literal: true

# A {Group} a member explicitly shared with an {McpConnection} when
# authorizing an assistant.
#
# Associations
# ------------
#
# |                  |                                       |
# |:-----------------|:--------------------------------------|
# | `mcp_connection` | The {McpConnection} granting access.  |
# | `group`          | The shared {Group}.                   |

class McpConnectionGroup < ApplicationRecord
  belongs_to :mcp_connection
  belongs_to :group
end
