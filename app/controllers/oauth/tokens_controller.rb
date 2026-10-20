# frozen_string_literal: true

# Exchanges authorization codes and refresh tokens for MCP access tokens, but
# only while the {McpConnection} they were issued under is still active and
# the requested `resource`, if any, is this MCP server.
#
# Refresh tokens rotate on every use. Presenting a refresh token that was
# rotated more than {REPLAY_GRACE_PERIOD} ago is treated as theft (OAuth 2.1
# §4.3.1): the whole connection is revoked, so neither the legitimate client
# nor whoever replayed the token keeps access. Within the grace period a reused
# token is only refused, so a client that refreshes concurrently keeps its grant.
#
# A client that revokes its current refresh token (RFC 7009) also revokes its
# connection, since nothing more can be issued under it.

class Oauth::TokensController < Doorkeeper::TokensController
  # How long a just-rotated refresh token may be presented again without
  # revoking its connection.
  REPLAY_GRACE_PERIOD = 5.seconds

  prepend_before_action :require_mcp_enabled!

  # Issues an access and refresh token pair.
  #
  # Routes
  # ------
  #
  # * `POST /oauth/token`
  #
  # Body Parameters
  # ---------------
  #
  # |                 |                                                                     |
  # |:----------------|:--------------------------------------------------------------------|
  # | `grant_type`    | `authorization_code` or `refresh_token`.                            |
  # | `client_id`     | The `client_id` returned by client registration.                    |
  # | `code`          | The authorization code (`authorization_code` only).                 |
  # | `redirect_uri`  | The redirect URI used to obtain the code (`authorization_code` only). |
  # | `code_verifier` | The PKCE verifier for the code (`authorization_code` only).         |
  # | `refresh_token` | The current refresh token (`refresh_token` only).                   |
  # | `resource`      | The MCP server URL (RFC 8707); defaults to the connection's.        |

  def create
    credential.mcp_connection.revoke! if replayed_refresh_token?
    return refuse_grant unless usable_credential?

    super
  end

  private

  def require_mcp_enabled!
    head :not_found unless Mcp::Configuration.enabled?
  end

  def credential
    return @credential if defined?(@credential)

    @credential = case params[:grant_type]
                    when "authorization_code" then Oauth::AccessGrant.by_token(params[:code])
                    when "refresh_token" then Oauth::AccessToken.by_refresh_token(params[:refresh_token])
                  end
  end

  def replayed_refresh_token?
    params[:grant_type] == "refresh_token" && credential&.revoked_at&.before?(REPLAY_GRACE_PERIOD.ago)
  end

  def usable_credential?
    credential&.mcp_connection&.active? && Mcp::Configuration.targets_resource?(params[:resource])
  end

  def revoke_token
    return super unless refresh_token_revocation? && revocable_token.revocable?

    revocable_token.token.mcp_connection.revoke!
  end

  def refresh_token_revocation? = revocable_token.kind_of?(Doorkeeper::RevocableTokens::RevocableRefreshToken)

  def refuse_grant
    response.headers["Cache-Control"] = "no-store"
    render json: {error: "invalid_grant"}, status: :bad_request
  end

  def authorized?
    server.client && token && server.client.application.id == token.application_id
  end
end
