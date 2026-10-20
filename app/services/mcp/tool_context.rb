# frozen_string_literal: true

# The identity behind one MCP request: the member's {McpConnection} and the
# access token presented for it. Every {Mcp::Tools} call goes through {#call},
# which rechecks consent, resolves the member's membership in the named group,
# dispatches the tool to {Mcp::GroupTools}, maps failures to tool errors, and
# writes an audit log line.

class Mcp::ToolContext
  # The scope that permits write tools.
  WRITE_SCOPE = "mcp:write"

  # @param token [Oauth::AccessToken] The validated bearer token for this
  #   request.

  def initialize(token)
    @token = token
    @connection = token.mcp_connection
  end

  # @return [Boolean] Whether both the token and its connection grant
  #   {WRITE_SCOPE}.

  def writable? = @token.includes_scope?(WRITE_SCOPE) && @connection.scopes.split.include?(WRITE_SCOPE)

  # Runs a tool as the connection's member, within the groups and scopes the
  # member consented to.
  #
  # @param name [String] The tool's name.
  # @param arguments [Hash{Symbol => Object}] The tool's validated arguments.
  # @param write [Boolean] Whether the tool acts on the member's behalf.
  # @return [MCP::Tool::Response] The tool's data, or an error result.

  def call(name, arguments, write:)
    audit(name, arguments) do
      authorize!(write:)
      success(data: invoke(name, arguments))
    rescue ActiveRecord::RecordNotFound
      failure(error: I18n.t("mcp.tool_context.errors.not_found"))
    rescue Groups::ActionError, Markets::Resolver::Error => e
      failure(error: e.message)
    rescue ActiveRecord::RecordInvalid => e
      failure(errors: e.record.errors.to_hash)
    end
  end

  private

  def authorize!(write:)
    raise Groups::ActionError, "group_scoping.errors.not_a_member" unless @connection.reload.active?
    raise Groups::ActionError, "mcp.tool_context.errors.read_only" if write && !writable?
  end

  def invoke(name, arguments)
    return Mcp::GroupTools.serialize(GroupSerializer, @connection.accessible_groups.order(:name)) if name == "list_groups"

    Mcp::GroupTools.new(membership_in(arguments.fetch(:group_id))).public_send(name, **arguments.except(:group_id))
  end

  def membership_in(subdomain)
    @connection.accessible_groups.find_by!(subdomain:).memberships.active.find_by!(user_id: @connection.user_id)
  end

  def audit(name, arguments)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
  ensure
    Rails.logger.info({event: "mcp.tool", tool: name, connection_id: @connection.id, user_id: @connection.user_id,
                       group: arguments[:group_id], success: result&.error? == false,
                       duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round}.to_json)
  end

  def success(data) = tool_response(data, error: false)
  def failure(data) = tool_response(data, error: true)

  def tool_response(data, error:)
    MCP::Tool::Response.new([{type: "text", text: data.to_json}], error:, structured_content: data)
  end
end
