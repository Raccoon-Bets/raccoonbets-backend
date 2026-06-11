# frozen_string_literal: true

# Registers and removes the current user's Web Push subscriptions (one per
# browser/device). Upsert on endpoint so re-subscribing is idempotent.
class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  # POST /account/push_subscriptions
  #
  # An endpoint is a per-browser push channel and is globally unique. Re-homing
  # one to the signed-in user is allowed on a shared device (where the same
  # browser is reused across accounts) — but only when the request re-presents
  # the channel's keys, proving possession of the channel rather than mere
  # knowledge of its bearer endpoint URL. A request that knows only the endpoint
  # cannot take over another user's subscription.
  def create
    p256dh = subscription_params.dig(:keys, :p256dh)
    auth   = subscription_params.dig(:keys, :auth)
    sub    = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])

    rehoming = sub.persisted? && sub.user_id != current_user.id
    if rehoming && !sub.keys_match?(p256dh:, auth:)
      Rails.logger.warn("[push] refused takeover of subscription ##{sub.id} by user ##{current_user.id}")
      return head :forbidden
    end

    sub.update!(user: current_user, p256dh_key: p256dh, auth_key: auth, user_agent: subscription_params[:user_agent])
    Rails.logger.info("[push] re-homed subscription ##{sub.id} to user ##{current_user.id}") if rehoming
    head :no_content
  end

  # DELETE /account/push_subscriptions
  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).delete_all
    head :no_content
  end

  private

  def subscription_params
    params.permit(:endpoint, :user_agent, keys: %i[p256dh auth])
  end
end
