# frozen_string_literal: true

# A group explicitly selected when authorizing an assistant.
class McpConnectionGroup < ApplicationRecord
  belongs_to :mcp_connection
  belongs_to :group
end
