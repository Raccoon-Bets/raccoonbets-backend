# frozen_string_literal: true

# Starts an OAuth authorization and carries its validated parameters to the
# website's consent screen.
#
# A request naming an unknown client or an unregistered redirect URI is refused
# with a JSON 400, because there is no trustworthy place to send the member.
# Once the client and redirect are known, every other problem is reported to
# the client by redirecting with `error` and `state` (RFC 6749 §4.1.2.1).

class Oauth::AuthorizationsController < Oauth::BaseController
  PARAMETERS = %i[client_id redirect_uri response_type scope state code_challenge code_challenge_method
                  resource].freeze
  private_constant :PARAMETERS

  # The longest value accepted for any authorization parameter.
  MAX_PARAMETER_LENGTH = 2048
  private_constant :MAX_PARAMETER_LENGTH

  # Redirects to a short-lived consent request without placing login tokens in
  # the URL.
  #
  # Routes
  # ------
  #
  # * `GET /oauth/authorize`
  #
  # Query Parameters
  # ----------------
  #
  # |                         |                                                                       |
  # |:------------------------|:----------------------------------------------------------------------|
  # | `client_id`             | The `client_id` returned by client registration.                      |
  # | `redirect_uri`          | One of the client's registered redirect URIs (any port on loopback).  |
  # | `response_type`         | `code`.                                                               |
  # | `scope`                 | Space-separated scopes; defaults to `mcp:read`.                       |
  # | `state`                 | Opaque client value echoed back on the redirect.                      |
  # | `code_challenge`        | The base64url SHA-256 PKCE challenge.                                 |
  # | `code_challenge_method` | `S256`.                                                               |
  # | `resource`              | The MCP server URL (RFC 8707); defaults to it when omitted.           |

  def create
    return invalid_request unless bounded_parameters? && pre_authorization.client_valid?
    return redirect_with_error(pre_authorization.error_response) unless pre_authorization.authorizable?
    return redirect_with_error(invalid_target) unless Mcp::Configuration.targets_resource?(parameters[:resource])
    return redirect_with_error(invalid_code_challenge) unless valid_code_challenge?

    redirect_to consent_url(create_pending_request), allow_other_host: true
  end

  private

  def parameters
    @parameters ||= params.permit(*PARAMETERS).to_h.symbolize_keys
  end

  def pre_authorization
    @pre_authorization ||= Doorkeeper::OAuth::PreAuthorization.new(Doorkeeper.configuration, parameters)
  end

  def bounded_parameters? = parameters.values.all? { it.length <= MAX_PARAMETER_LENGTH }
  def valid_code_challenge? = parameters[:code_challenge].match?(/\A[A-Za-z0-9_-]{43}\z/)

  def create_pending_request
    McpAuthorizationRequest.create!(identifier: SecureRandom.urlsafe_base64(32),
                                    parameters: parameters.merge(resource: Mcp::Configuration.resource),
                                    expires_at: 10.minutes.from_now)
  end

  def consent_url(pending) = "#{Rails.application.config.urls.frontend}/oauth/consent/#{pending.identifier}"

  def invalid_target
    Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_target, state: parameters[:state],
                                         redirect_uri: parameters[:redirect_uri])
  end

  def invalid_code_challenge
    Doorkeeper::OAuth::InvalidRequestResponse.new(reason: :unknown, state: parameters[:state],
                                                  redirect_uri: parameters[:redirect_uri])
  end

  def redirect_with_error(error)
    return invalid_request(error.name.to_s) unless error.redirectable?

    redirect_to error.redirect_uri, allow_other_host: true
  end
end
