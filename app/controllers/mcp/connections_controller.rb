# frozen_string_literal: true

# Lets members inspect and revoke assistant connections using their website login.
class Mcp::ConnectionsController < ApplicationController
  before_action :authenticate_user!

  # Lists connections, including expiry and revocation, without exposing credentials.
  def index
    render json: {enabled: Mcp::Configuration.enabled?, connections: connections.includes(:application, :groups).order(created_at: :desc).map do |connection|
      {id: connection.id, client_name: connection.application.name, scopes: connection.scopes.split,
       groups: connection.groups.map { {id: it.id, name: it.name} },
       expires_at: connection.expires_at, revoked_at: connection.revoked_at}
    end}
  end

  # Revokes all access and refresh credentials associated with this connection.
  def destroy
    connections.find(params.expect(:id)).revoke!
    head :no_content
  end

  private

  def connections = McpConnection.where(user: current_user)
end
