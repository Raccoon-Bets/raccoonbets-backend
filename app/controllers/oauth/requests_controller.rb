# frozen_string_literal: true

# Authenticated browser consent for a pending OAuth request.
class Oauth::RequestsController < Oauth::BaseController
  before_action :authenticate_user!
  before_action :require_open_account!
  before_action :find_request

  # Presents the client identity, requested access, and selectable groups.
  def show
    @pending.with_lock do
      return head :not_found unless @pending.available_to?(current_user)

      @pending.update!(user: current_user)
      render json: {
          client_name: application.name, redirect_uri: @pending.parameters.fetch("redirect_uri"),
        write_requested: requested_scopes.include?("mcp:write"),
        groups: available_groups.order(:name).map { {id: it.id, name: it.name} }
      }
    end
  end

  # Consumes the request once, issuing a code only for the member's explicit selection.
  def decision
    @pending.with_lock do
      return head :not_found unless @pending.available_to?(current_user)

      if params[:approve] == false
        @pending.update!(consumed_at: Time.current, user: current_user)
        return render json: {redirect_uri: denial_redirect}
      end
      return invalid_request unless params[:approve] == true && valid_groups?
      return invalid_request if params[:write] == true && requested_scopes.exclude?("mcp:write")

      scopes = (params[:write] == true) ? "mcp:read mcp:write" : "mcp:read"
      connection = McpConnection.create!(user: current_user, application:, scopes:, resource: Mcp::Configuration.resource,
                                         expires_at: 30.days.from_now, groups: selected_groups)
      attributes = @pending.parameters.symbolize_keys.merge(scope: scopes, mcp_connection_id: connection.id)
      pre_auth = Doorkeeper::OAuth::PreAuthorization.new(Doorkeeper.configuration, attributes, current_user)
      raise ActiveRecord::RecordInvalid, connection unless pre_auth.authorizable?

      result = Doorkeeper::OAuth::CodeRequest.new(pre_auth, current_user).authorize
      @pending.update!(consumed_at: Time.current, user: current_user)
      render json: {redirect_uri: result.redirect_uri}
    end
  end

  private

  def require_open_account!
    head :unauthorized unless current_user&.status_id == 2
  end

  def find_request
    @pending = McpAuthorizationRequest.find_by!(identifier: params.expect(:id))
  end

  def application = Doorkeeper::Application.find_by!(uid: @pending.parameters.fetch("client_id"))
  def requested_scopes = @pending.parameters.fetch("scope", "mcp:read").split
  def available_groups = current_user.groups.active.merge(Membership.active)
  def selected_groups = available_groups.where(id: params[:group_ids])

  def valid_groups?
    ids = params[:group_ids]
    ids.kind_of?(Array) && ids.any? && ids.all?(Integer) && selected_groups.count == ids.uniq.length
  end

  def denial_redirect
    uri = URI(@pending.parameters.fetch("redirect_uri"))
    query = URI.decode_www_form(uri.query.to_s) + [%w[error access_denied]]
    query << ["state", @pending.parameters["state"]] if @pending.parameters["state"]
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end
end
