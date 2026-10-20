# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record
  api_only
  grant_flows %w[authorization_code]
  force_pkce
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
