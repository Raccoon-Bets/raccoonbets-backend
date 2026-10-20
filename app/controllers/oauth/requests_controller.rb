# frozen_string_literal: true

# The website's consent screen API for a pending {McpAuthorizationRequest}.
# A signed-in member with an open account reviews the client's request, picks
# the {Group}s to share and whether to allow writes, and approves or denies it.
# Approving creates the {McpConnection} and issues the authorization code.
#
# Errors render `{"error": "<code>"}`: `request_unavailable` (404) when the
# request is unknown, expired, already decided, or claimed by another member;
# `account_unavailable` (403) when the member's account is not open; and
# `invalid_request` (400) for a malformed decision.

class Oauth::RequestsController < Oauth::BaseController
  before_action :authenticate_user!
  before_action :require_open_account!
  before_action :find_request

  # Shows the client, the access it requests, the member's selectable groups,
  # and the account granting access. Claims the request for this member.
  #
  # Routes
  # ------
  #
  # * `GET /oauth/requests/:id`

  def show
    @pending.with_lock do
      return request_unavailable unless @pending.available_to?(current_user)

      @pending.update!(user: current_user)
      assign_consent
      render :show, formats: :json
    end
  end

  # Consumes the request once. Denying returns the client's error redirect;
  # approving issues a code for exactly the member's selection.
  #
  # Routes
  # ------
  #
  # * `POST /oauth/requests/:id/decision`
  #
  # Body Parameters
  # ---------------
  #
  # |             |                                                                  |
  # |:------------|:-----------------------------------------------------------------|
  # | `approve`   | `true` to grant access, `false` to deny it.                      |
  # | `group_ids` | The IDs of the member's active groups to share (when approving). |
  # | `write`     | `true` to also grant `mcp:write`, if the client requested it.    |

  def decision
    @pending.with_lock do
      return request_unavailable unless @pending.available_to?(current_user)
      return deny if params[:approve] == false
      return invalid_request unless approvable?

      approve
    end
  end

  private

  def require_open_account!
    render json: {error: "account_unavailable"}, status: :forbidden unless current_user&.open?
  end

  def find_request
    @pending = McpAuthorizationRequest.find_by(identifier: params[:id])
    request_unavailable unless @pending
  end

  def request_unavailable = render(json: {error: "request_unavailable"}, status: :not_found)

  def assign_consent
    @application = application
    @redirect_uri = @pending.parameters.fetch("redirect_uri")
    @write_requested = write_requested?
    @groups = available_groups.order(:name)
    @account = current_user
  end

  def deny
    consume!
    render json: {redirect_uri: denial_redirect}
  end

  def approvable?
    params[:approve] == true && valid_groups? && (!write_granted? || write_requested?) &&
      pre_authorization.authorizable?
  end

  def approve
    pre_authorization.custom_access_token_attributes[:mcp_connection_id] = create_connection.id
    authorization = Doorkeeper::OAuth::CodeRequest.new(pre_authorization, current_user).authorize
    consume!
    render json: {redirect_uri: authorization.redirect_uri}
  end

  def consume! = @pending.update!(consumed_at: Time.current, user: current_user)

  def create_connection
    McpConnection.create!(user: current_user, application:, scopes: granted_scopes,
                          resource: Mcp::Configuration.resource, expires_at: McpConnection::LIFETIME.from_now,
                          groups: selected_groups)
  end

  def pre_authorization
    @pre_authorization ||= Doorkeeper::OAuth::PreAuthorization.new(Doorkeeper.configuration, authorization_parameters,
                                                                   current_user)
  end

  def authorization_parameters = @pending.parameters.symbolize_keys.merge(scope: granted_scopes)

  def application
    @application ||= Doorkeeper::Application.find_by!(uid: @pending.parameters.fetch("client_id"))
  end

  def requested_scopes = @pending.parameters.fetch("scope", "mcp:read").split
  def write_requested? = requested_scopes.include?("mcp:write")
  def write_granted? = params[:write] == true
  def granted_scopes = (write_granted? ? Mcp::Configuration::SCOPES : %w[mcp:read]).join(" ")
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
