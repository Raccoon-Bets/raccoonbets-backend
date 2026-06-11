# frozen_string_literal: true

module WebPush
  # Delivers a single push payload to one subscription. Removes subscriptions the
  # push service reports as gone; other errors retry a few times then give up.
  class DeliverJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # @param subscription_id [Integer]
    # @param payload [Hash] { title:, body:, url:, tag? }
    def perform(subscription_id, payload)
      subscription = PushSubscription.find_by(id: subscription_id)
      return if subscription.nil?

      ::WebPush.payload_send(
        message:  payload.to_json,
        endpoint: subscription.endpoint,
        p256dh:   subscription.p256dh_key,
        auth:     subscription.auth_key,
        vapid:    {
            subject:     Rails.application.credentials.dig(:vapid, :subject),
            public_key:  Rails.application.credentials.dig(:vapid, :public_key),
            private_key: Rails.application.credentials.dig(:vapid, :private_key)
        },
        ttl:      24 * 60 * 60
      )
    rescue ::WebPush::ExpiredSubscription, ::WebPush::InvalidSubscription
      subscription&.destroy
    end
  end
end
