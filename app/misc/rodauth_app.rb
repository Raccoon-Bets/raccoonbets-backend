# frozen_string_literal: true

require "sequel/core"

class RodauthApp < Rodauth::Rails::App
  configure do
    # ── Database ──────────────────────────────────────────────────────────

    db Sequel.postgres(extensions: :activerecord_connection, keep_reference: false)

    # ── Features ──────────────────────────────────────────────────────────

    enable :login, :logout, :create_account, :close_account,
           :verify_account,
           :reset_password, :change_password, :change_login,
           :jwt, :jwt_refresh,
           :webauthn, :webauthn_login, :webauthn_autofill,
           :omniauth

    # ── Account table ─────────────────────────────────────────────────────

    accounts_table :users
    account_password_hash_column :password_hash
    account_status_column :status_id
    account_open_status_value 2
    account_unverified_status_value 1
    account_closed_status_value 3
    login_column :email

    # ── Routes ────────────────────────────────────────────────────────────

    login_route "login"
    logout_route "logout"
    create_account_route "signup"
    verify_account_route "verify-account"
    reset_password_request_route "password-resets"
    reset_password_route "reset-password"
    # jwt_refresh_route uses default "jwt-refresh"
    close_account_route nil
    change_password_route nil
    change_login_route nil
    # WebAuthn routes (built-in):
    #   POST /webauthn-setup   — register a passkey (authenticated)
    #   POST /webauthn-login   — passwordless login with passkey
    #   POST /webauthn-remove  — handled by our passkeys controller
    webauthn_auth_route nil     # 2FA challenge flow, not used
    webauthn_remove_route nil   # handled by PasskeysController

    # ── JWT ───────────────────────────────────────────────────────────────

    jwt_secret Rails.application.credentials.jwt_secret
    jwt_access_token_period 900 # 15 minutes
    jwt_refresh_token_deadline_interval days: 30

    # The refresh route must accept the (already-expired) access token alongside
    # the refresh token; that is the whole point of refreshing. Without this,
    # refreshing is only possible while the access token is still valid.
    allow_refresh_with_expired_jwt_access_token? true

    # Signal an expired access token as 401 rather than Rodauth's default 400,
    # so the client treats it as an auth challenge and refreshes transparently.
    expired_jwt_access_token_status 401

    # Include email in JWT payload for Action Cable.
    jwt_session_hash do
      h = super()
      # The OmniAuth routes run in cookie-session mode (see only_json? below),
      # where `session` is an ActionDispatch session object rather than the
      # plain hash JWT mode provides. Coerce it so JWT.encode serializes the
      # claims instead of the object's #to_s.
      h = h.to_hash unless h.kind_of?(Hash)
      h["e"] = account[:email] if account
      h
    end

    # Suppress the empty JWT that Rodauth would otherwise emit when the
    # session contains no account_id (e.g. after an unverified signup or
    # a failed login attempt).
    set_jwt_token do |token|
      super(token) if session[session_key]
    end

    # ── JWT refresh keys table ────────────────────────────────────────────

    jwt_refresh_token_table :account_jwt_refresh_keys
    jwt_refresh_token_id_column :id
    jwt_refresh_token_account_id_column :user_id
    jwt_refresh_token_key_column :key
    jwt_refresh_token_deadline_column :deadline

    # ── Password ──────────────────────────────────────────────────────────

    password_minimum_length 6
    password_maximum_length 128
    require_password_confirmation? false
    require_login_confirmation? false

    # ── JSON API mode ─────────────────────────────────────────────────────
    # Everything is a stateless JSON/JWT endpoint except the OmniAuth routes
    # under /auth, which are browser redirects with no Authorization header.
    # Forcing JSON/JWT there would make OmniAuth stash the OAuth `state` in a
    # JWT that never returns on the provider callback, so those routes fall
    # back to the cookie session instead (see the OmniAuth section below).

    only_json? { !request.path.start_with?("#{omniauth_prefix}/") }

    # ── Email ─────────────────────────────────────────────────────────────

    email_from "donotreply@raccoonbets.org"

    # Resolves the frontend origin a flow started on (the apex or a group
    # subdomain), validated against the trusted set so emailed links and
    # redirects can't be pointed at an attacker-controlled host.
    trusted_frontend_origin = ->(origin) do
      patterns = Rails.application.config.x.frontend_origin_patterns
      trusted = origin.present? && patterns.any? do |pattern|
        pattern.kind_of?(Regexp) ? pattern.match?(origin) : pattern == origin
      end
      trusted ? origin : Rails.application.config.urls.frontend
    end

    send_reset_password_email do
      frontend = Rails.application.config.urls.frontend
      token_key = convert_email_token_key(reset_password_key_value)
      token = "#{account_id}#{token_separator}#{token_key}"
      link = "#{frontend}/reset-password?key=#{token}"
      RodauthMailer.reset_password(account[:email], link, account[:locale]).deliver_now
    end

    # Signup is a CORS request from the SPA, so the Origin header carries the
    # host the visitor signed up on; the verification link returns them there
    # (a group subdomain keeps its join-intent and return-to state).
    send_verify_account_email do
      frontend = trusted_frontend_origin.call(request.env["HTTP_ORIGIN"])
      token_key = convert_email_token_key(verify_account_key_value)
      token = "#{account_id}#{token_separator}#{token_key}"
      link = "#{frontend}/verify-account?key=#{token}"
      RodauthMailer.verify_account(account[:email], link, account[:locale]).deliver_now
    end

    # ── WebAuthn ──────────────────────────────────────────────────────────
    # The RP id is the frontend's registrable domain (raccoonbets.org in
    # production, lvh.me in development), so one passkey works on the apex
    # and on every group subdomain.

    webauthn_origin { Rails.application.config.urls.frontend }
    webauthn_rp_id { URI.parse(Rails.application.config.urls.frontend).host }
    webauthn_rp_name "Raccoon Bets"

    webauthn_keys_account_id_column :account_id
    webauthn_keys_webauthn_id_column :webauthn_id
    webauthn_keys_public_key_column :public_key
    webauthn_keys_sign_count_column :sign_count
    webauthn_keys_last_use_column :last_use

    # ── OmniAuth (social login) ───────────────────────────────────────────
    # Google and Apple sign-in via rodauth-omniauth. The OAuth handshake runs
    # in cookie-session mode (see only_json? above); on success after_login
    # mints the same JWT access + refresh token pair a password login issues
    # and hands them to the SPA through a redirect fragment, keeping the rest
    # of the app stateless. An identity whose verified email matches an
    # existing account links to it; otherwise a new, already-verified account
    # is created (the provider vouches for the email).

    omniauth_identities_account_id_column :user_id

    omniauth_provider :google_oauth2,
                      Rails.application.credentials.dig(:google, :client_id),
                      Rails.application.credentials.dig(:google, :client_secret),
                      scope:  "email,profile",
                      prompt: "select_account",
                      name:   "google"

    omniauth_provider :apple,
                      Rails.application.credentials.dig(:apple, :client_id),
                      "", # client secret is a JWT the strategy generates from the key below
                      scope:   "email name",
                      team_id: Rails.application.credentials.dig(:apple, :team_id),
                      key_id:  Rails.application.credentials.dig(:apple, :key_id),
                      pem:     Rails.application.credentials.dig(:apple, :private_key),
                      name:    "apple"

    # The SPA starts the request phase with a cross-origin form POST and so
    # can't present a Rails CSRF token; the OAuth `state` parameter, which both
    # strategies validate on the callback, is what guards the flow instead.
    omniauth_request_validation_phase do
      # Intentionally a no-op: the OAuth state parameter is the CSRF defense.
    end

    # rodauth-omniauth already inserts a new account with the open status, so
    # we only supply the non-null name (falling back to the email local-part
    # when the provider withholds it, e.g. Apple after the first sign-in) and
    # timestamps.
    before_omniauth_create_account do
      account[:name] = omniauth_name.presence || omniauth_email.to_s.split("@").first
      account[:created_at] = Time.current
      account[:updated_at] = Time.current
    end

    # Matching an existing *unverified* account verifies it (the provider
    # confirmed the address); a *closed* account must not be resurrected, so
    # exclude it and let it fall through to the failure redirect.
    omniauth_verify_account? do
      super() && account[account_status_column] == account_unverified_status_value
    end

    # The OmniAuth request phase recorded the SPA origin the flow started on;
    # the post-auth redirect returns there once it passes the trusted set.
    oauth_frontend_origin = -> { trusted_frontend_origin.call(omniauth_origin) }

    # Send OmniAuth failures (denied consent, closed/unmatched account) to the
    # SPA's callback with an error rather than Rodauth's default HTML flash.
    omniauth_failure_redirect do
      "#{instance_exec(&oauth_frontend_origin)}/oauth/callback#error=failed"
    end
    omniauth_login_failure_redirect do
      "#{instance_exec(&oauth_frontend_origin)}/oauth/callback#error=failed"
    end

    # ── Turnstile (Cloudflare CAPTCHA) ────────────────────────────────────

    require_turnstile = -> do
      next if Rails.env.test?

      token = param_or_nil("turnstile_token")
      unless TurnstileVerifier.verify(token, request.ip).success?
        response.status = 400
        response["Content-Type"] = "application/json"
        response.write({"error" => "captcha verification failed"}.to_json)
        request.halt
      end
    end

    # ── Captcha gates ────────────────────────────────────────────────────
    # Use *_route hooks so the captcha is required before Rodauth's account
    # lookup. Otherwise a bot can submit a nonexistent or already-taken
    # email, get the standard 401/422 back, and never need to solve the
    # widget — turning these endpoints into a free enumeration oracle.

    before_create_account_route do
      instance_exec(&require_turnstile) if request.post?
    end

    before_login_route do
      instance_exec(&require_turnstile) if request.post?
    end

    # ── Account creation ──────────────────────────────────────────────────

    before_create_account do
      account[:name] = param("name")
      locale = param_or_nil("locale")
      account[:locale] = locale if User::SUPPORTED_LOCALES.include?(locale)
      account[:created_at] = Time.current
      account[:updated_at] = Time.current
    end

    # :verify_account suppresses autologin until the account is verified.
    create_account_autologin? false
    # Password is captured at signup, not at verification time.
    verify_account_set_password? false

    # ── Account closure ───────────────────────────────────────────────────

    delete_account_on_close? true

    # ── Response customization ────────────────────────────────────────────
    # Add user profile data to the login response.

    after_login do
      if omniauth_auth
        # update_session (jwt_refresh) has already minted the refresh token and
        # written its hmac into the session, so session_jwt now produces a
        # fully refreshable access token. Hand both to the SPA in the redirect
        # fragment, where they never reach server logs or the Referer header.
        query = URI.encode_www_form(
          access_token:  session_jwt,
          refresh_token: json_response[jwt_refresh_token_key]
        )
        redirect "#{instance_exec(&oauth_frontend_origin)}/oauth/callback##{query}"
      else
        user = User.find(account_id)
        json_response["name"] = user.name
        json_response["email"] = user.email
        json_response["passkeys"] = user.webauthn_keys.order(:last_use).map do |k|
          {"id" => k.webauthn_id, "label" => k.label, "last_used_at" => k.last_use}
        end
      end
    end

    # Apply an optional label to a newly registered passkey.
    after_webauthn_setup do
      label = param_or_nil("label")
      if label.present?
        AccountWebauthnKey.where(account_id: account_id).
            order(:last_use).
            last&.update(label: label)
      end
    end

    # Prevent email enumeration on password reset requests.
    # Always return 204 regardless of whether the email exists.
    before_reset_password_request_route do
      if request.post?
        instance_exec(&require_turnstile)
        if (login = param_or_nil(login_param)) && account_from_login(login) && open_account? && !reset_password_email_recently_sent?
          generate_reset_password_key_value
          transaction do
            create_reset_password_key
            send_reset_password_email
          end
        end
        response.status = 204
        response.write("")
        request.halt
      end
    end
  end

  route(&:rodauth)
end
