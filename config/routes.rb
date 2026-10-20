# frozen_string_literal: true

Rails.application.routes.draw do
  match "/mcp", to: "mcp/server#handle", via: %i[get post delete]

  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#show"
  get "/.well-known/oauth-protected-resource/mcp", to: "oauth/metadata#resource"
  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#resource"
  get "/oauth/authorize", to: "oauth/authorizations#create"
  post "/oauth/register", to: "oauth/registrations#create"
  post "/oauth/token", to: "oauth/tokens#create"
  post "/oauth/revoke", to: "oauth/tokens#revoke"
  get "/oauth/requests/:id", to: "oauth/requests#show"
  post "/oauth/requests/:id/decision", to: "oauth/requests#decision"
  resources :mcp_connections, path: "account/mcp_connections", only: %i[index destroy], controller: "mcp/connections"
  # ── Rodauth handles: ────────────────────────────────────────────────
  # POST /login          — authenticate with email/password
  # POST /logout         — revoke session/refresh token
  # POST /signup         — create account
  # POST /verify-account — verify account with emailed token
  # POST /password-resets — request password reset email
  # POST /reset-password — reset password with token
  # POST /jwt-refresh    — refresh access token
  # POST /webauthn-setup — register a passkey (authenticated)
  # POST /webauthn-login — passwordless login with passkey

  # ── Account management ──────────────────────────────────────────────

  get "account" => "accounts#show"
  put "account" => "accounts#update"
  patch "account" => "accounts#update"
  delete "account" => "accounts#destroy"

  # ── Passkey management ──────────────────────────────────────────────
  # Rodauth handles registration (POST /webauthn-setup) and login
  # (POST /webauthn-login). Listing, renaming, and removing passkeys
  # happens through PasskeysController.

  resources :passkeys, path: "account/passkeys", only: %i[index update destroy],
                        param: :webauthn_id

  # ── Web Push subscriptions (current user's browsers) ─────────────────
  post "account/push_subscriptions"   => "push_subscriptions#create"
  delete "account/push_subscriptions" => "push_subscriptions#destroy"

  # ── Groups ──────────────────────────────────────────────────────────
  # `:group_id` is the group's subdomain slug throughout.

  resources :groups, only: %i[index create show update], param: :group_id do
    get :availability, on: :collection
  end

  scope "groups/:group_id", module: "groups", as: "group" do
    resources :members, only: %i[index update destroy]
    resources :join_requests, only: %i[index create destroy] do
      post :approve, on: :member
    end
    resources :invitations, only: %i[index create destroy]
    resources :markets, only: %i[index create show update destroy] do
      resource :position, only: %i[update destroy]
      resources :positions, only: :destroy, controller: "admin_positions", as: :admin_positions
      resource :resolution, only: %i[create update destroy]
      resources :comments, only: %i[create destroy]
    end
    get "balances" => "balances#index"
    get "settle_up" => "settle_up#show"
    resources :settlements, only: %i[index create destroy]
  end

  # ── Invitation acceptance (global; invitees aren't members yet) ────────

  get "invitations/:token" => "invitations#show", as: :invitation
  post "invitations/:token/accept" => "invitations#accept", as: :invitation_acceptance

  # ── Superadmin ──────────────────────────────────────────────────────

  namespace :admin do
    resources :groups, only: %i[index update destroy]
  end

  # ── Cypress test helpers ────────────────────────────────────────────

  if Rails.env.cypress?
    get "__cypress__/reset" => Cypress::Reset.new
    get "__cypress__/last_email" => Cypress::LastEmail.new
    get "__cypress__/lock_market" => Cypress::LockMarket.new
  end

  # ── Health & metrics ────────────────────────────────────────────────

  get "up" => "rails/health#show", as: :rails_health_check

  # Frontend warm-up ping; goes through the verify-* middlewares so a hit
  # here wakes Postgres and Redis pools alongside the Fly machine itself.
  get "presence" => "presence#show"

  get "metrics" => "metrics#show" unless Rails.env.test? || Rails.env.cypress?

  root to: redirect(Rails.application.config.urls.frontend)
end
