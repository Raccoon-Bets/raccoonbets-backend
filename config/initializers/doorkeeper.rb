# frozen_string_literal: true

# Treats `localhost` as a loopback host alongside loopback IP literals, so a
# native client's `http://localhost` redirect may use any port (RFC 8252 §7.3)
# and skips the HTTPS requirement below. Claude Code registers that form.
module LocalhostLoopbackRedirects
  # @param uri [URI::Generic] a redirect URI.
  # @return [Boolean] whether the URI's host is `localhost` or a loopback address.
  def loopback_uri?(uri) = uri.host&.downcase == "localhost" || super
end
Doorkeeper::OAuth::Helpers::URIChecker.singleton_class.prepend(LocalhostLoopbackRedirects)

Doorkeeper.configure do
  orm :active_record
  api_only
  grant_flows %w[authorization_code]
  force_pkce
  pkce_code_challenge_methods %w[S256]
  force_ssl_in_redirect_uri { !Doorkeeper::OAuth::Helpers::URIChecker.loopback_uri?(it) }
  hash_token_secrets
  hash_application_secrets
  use_refresh_token
  authorization_code_expires_in 5.minutes
  access_token_expires_in 15.minutes
  default_scopes :"mcp:read"
  optional_scopes :"mcp:write"
  enforce_configured_scopes
  custom_access_token_attributes %i[mcp_connection_id]
  access_token_class "Oauth::AccessToken"
  access_grant_class "Oauth::AccessGrant"
  resource_owner_authenticator { current_user }
end
