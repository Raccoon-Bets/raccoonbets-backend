# frozen_string_literal: true

# Manages the current user's registered passkey (WebAuthn) credentials.
# Registration and login are handled by Rodauth's built-in routes
# (`/webauthn-setup` and `/webauthn-login`).

class PasskeysController < ApplicationController
  before_action :authenticate_user!

  # GET /account/passkeys
  def index
    render json: current_user.webauthn_keys.order(:last_use).map { |key| passkey_json(key) }
  end

  # PATCH /account/passkeys/:webauthn_id
  def update
    key = current_user.webauthn_keys.find_by!(webauthn_id: params.expect(:webauthn_id))
    key.update!(label: params[:label])
    render json: passkey_json(key)
  end

  # DELETE /account/passkeys/:webauthn_id
  def destroy
    key = current_user.webauthn_keys.find_by!(webauthn_id: params.expect(:webauthn_id))
    key.destroy!
    head :no_content
  end

  private

  def passkey_json(key)
    {id: key.webauthn_id, label: key.label, last_used_at: key.last_use}
  end
end
