# frozen_string_literal: true

# Lets members review and revoke the assistant connections they have approved,
# using their website login. Only {McpConnection.usable} connections are
# listed; revoked, expired, and never-redeemed ones are hidden.

class Mcp::ConnectionsController < ApplicationController
  before_action :authenticate_user!

  # Lists the member's usable connections, newest first, along with whether
  # the MCP server is enabled and the URL assistants should connect to.
  #
  # Routes
  # ------
  #
  # * `GET /account/mcp_connections.json`

  def index
    @connections = connections.usable.includes(:application, :groups).order(created_at: :desc)
    respond_with @connections
  end

  # Revokes the connection and every access and refresh token issued through it.
  #
  # Routes
  # ------
  #
  # * `DELETE /account/mcp_connections/:id.json`

  def destroy
    connections.find(params.expect(:id)).revoke!
    head :no_content
  end

  private

  def connections = McpConnection.where(user: current_user)
end
