# frozen_string_literal: true

# An MCP server that answers calls to every tool but lists only those the
# connection may use. Assistants can keep a tool list from an earlier, broader
# connection; a call to an unlisted tool still reaches {Mcp::ToolContext},
# which explains why it was refused instead of reporting an unknown tool.

class Mcp::MemberServer < MCP::Server
  # Takes the {MCP::Server} options, with every callable tool as `tools:`.
  #
  # @param listed_tools [Array<Class<MCP::Tool>>] The tools `tools/list`
  #   declares; the rest of `tools:` stay callable but undeclared.

  def initialize(listed_tools:, **)
    super(**)
    @listed_tool_names = listed_tools.map(&:name_value)
  end

  private

  def list_tools(request)
    result = super
    result.merge(tools: result[:tools].select { @listed_tool_names.include?(it[:name]) })
  end
end
