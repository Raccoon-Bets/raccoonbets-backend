# frozen_string_literal: true

# Registers public OAuth clients for the PKCE-only MCP authorization flow.
class Oauth::RegistrationsController < Oauth::BaseController
  # Creates a client after validating its redirect and grant metadata.
  def create
    return invalid_request("invalid_client_metadata") unless valid_metadata?

    application = Doorkeeper::Application.create!(name: params[:client_name], redirect_uri: redirects.join("\n"),
                                                  confidential: false, scopes: "mcp:read mcp:write")
    render json: {client_id: application.uid, client_name: application.name, redirect_uris: redirects,
                  token_endpoint_auth_method: "none", grant_types: %w[authorization_code refresh_token],
                  response_types: %w[code], scope: application.scopes.to_s}, status: :created
  rescue ActiveRecord::RecordInvalid
    invalid_request("invalid_client_metadata")
  end

  private

  def redirects = params[:redirect_uris]

  def valid_metadata?
    name = params[:client_name]
    name.kind_of?(String) && name.length.between?(1, 200) &&
      params.fetch(:token_endpoint_auth_method, "none") == "none" &&
      params.fetch(:response_types, %w[code]) == %w[code] &&
      params.fetch(:grant_types, %w[authorization_code refresh_token]).kind_of?(Array) &&
      (params.fetch(:grant_types, %w[authorization_code refresh_token]) - %w[authorization_code refresh_token]).empty? &&
      redirects.kind_of?(Array) && redirects.length.between?(1, 10) && redirects.all? { valid_redirect?(it) }
  end

  def valid_redirect?(value)
    return false unless value.kind_of?(String) && value.length <= 2048 && !value.match?(/[\s\\]/)

    uri = URI.parse(value)
    uri.kind_of?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    false
  end
end
