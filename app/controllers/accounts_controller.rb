# frozen_string_literal: true

# RESTful controller for viewing and managing the current User's account.

class AccountsController < ApplicationController
  before_action :authenticate_user!

  SCALAR_ACCOUNT_KEYS = %i[name email locale venmo_handle paypal_handle cashapp_cashtag].freeze

  # GET /account
  def show
    render json: account_json(current_user)
  end

  # PUT/PATCH /account
  def update
    current_user.assign_attributes(account_params) if scalar_account_params?
    if (raw_prefs = params.dig(:user, :notification_preferences))
      current_user.notification_preferences = NotificationPreferences.sanitize(raw_prefs.to_unsafe_h)
    end

    if current_user.save
      render json: account_json(current_user)
    else
      render json: {errors: current_user.errors}, status: :unprocessable_content
    end
  end

  # DELETE /account
  def destroy
    current_user.destroy
    head :no_content
  end

  private

  def scalar_account_params?
    user_params = params[:user]
    user_params.present? && SCALAR_ACCOUNT_KEYS.any? { |k| user_params.key?(k) }
  end

  def account_params
    params.expect(user: SCALAR_ACCOUNT_KEYS)
  end

  def account_json(user)
    {
        name:                     user.name,
        email:                    user.email,
        locale:                   user.locale,
        venmo_handle:             user.venmo_handle,
        paypal_handle:            user.paypal_handle,
        cashapp_cashtag:          user.cashapp_cashtag,
        passkeys:                 user.webauthn_keys.order(:last_use).map do |k|
          {id: k.webauthn_id, label: k.label, last_used_at: k.last_use}
        end,
        notification_preferences: user.notification_preferences_object.as_json,
        vapid_public_key:         Rails.application.credentials.dig(:vapid, :public_key)
    }
  end
end
