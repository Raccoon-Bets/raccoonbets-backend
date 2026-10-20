# frozen_string_literal: true

# Registers public OAuth clients for the PKCE-only MCP authorization flow
# (RFC 7591 dynamic client registration).
#
# Redirect URIs must use `https`, except that native clients may use `http`
# on a loopback host (RFC 8252 §7.3).

class Oauth::RegistrationsController < Oauth::BaseController
  # Creates a client after validating its redirect and grant metadata.
  #
  # Routes
  # ------
  #
  # * `POST /oauth/register`
  #
  # Body Parameters
  # ---------------
  #
  # |                              |                                                              |
  # |:-----------------------------|:-------------------------------------------------------------|
  # | `client_name`                | The name shown to members on the consent screen (1–200).     |
  # | `redirect_uris`              | 1–10 `https` or loopback `http` redirect URIs.               |
  # | `token_endpoint_auth_method` | `none`, if given.                                            |
  # | `response_types`             | `["code"]`, if given.                                        |
  # | `grant_types`                | A subset of `authorization_code` and `refresh_token`.        |

  def create
    return invalid_request("invalid_client_metadata") unless valid_metadata?

    application = Doorkeeper::Application.create!(name: params[:client_name], redirect_uri: redirects.join("\n"),
                                                  confidential: false, scopes: Mcp::Configuration::SCOPES.join(" "))
    render json:   {client_id:                  application.uid,
                    client_name:                application.name,
                    redirect_uris:              redirects,
                    token_endpoint_auth_method: "none",
                    grant_types:                Mcp::Configuration::GRANT_TYPES,
                    response_types:             %w[code],
                    scope:                      application.scopes.to_s},
           status: :created
  rescue ActiveRecord::RecordInvalid
    invalid_request("invalid_client_metadata")
  end

  private

  def redirects = params[:redirect_uris]

  def valid_metadata?
    valid_client_name? && valid_grant_metadata? &&
      redirects.kind_of?(Array) && redirects.length.between?(1, 10) && redirects.all? { valid_redirect?(it) }
  end

  def valid_client_name?
    name = params[:client_name]
    name.kind_of?(String) && name.length.between?(1, 200)
  end

  def valid_grant_metadata?
    grant_types = params.fetch(:grant_types, Mcp::Configuration::GRANT_TYPES)
    params.fetch(:token_endpoint_auth_method, "none") == "none" &&
      params.fetch(:response_types, %w[code]) == %w[code] &&
      grant_types.kind_of?(Array) && (grant_types - Mcp::Configuration::GRANT_TYPES).empty?
  end

  def valid_redirect?(value)
    return false unless value.kind_of?(String) && value.length <= 2048 && !value.match?(/[\s\\]/)

    uri = URI.parse(value)
    allowed_scheme?(uri) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end

  def allowed_scheme?(uri)
    uri.kind_of?(URI::HTTPS) || (uri.kind_of?(URI::HTTP) && Doorkeeper::OAuth::Helpers::URIChecker.loopback_uri?(uri))
  end
end
