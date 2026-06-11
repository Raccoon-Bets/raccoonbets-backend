# frozen_string_literal: true

# A browser/device's Web Push subscription for a User. One row per endpoint; a
# user may have several (one per browser). Deleted when the push service reports
# the endpoint as gone (see WebPush::DeliverJob).
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, :p256dh_key, :auth_key, presence: true
  validates :endpoint, uniqueness: true

  # Whether the supplied push keys match this subscription's, proving the caller
  # possesses the browser channel itself rather than merely knowing its (bearer)
  # endpoint URL. Gates re-homing an endpoint to a different user on a shared
  # device. Compared in constant time so a mismatch can't be timed out.
  #
  # @param p256dh [String, nil] the client's ECDH public key
  # @param auth [String, nil] the client's auth secret
  # @return [Boolean]
  def keys_match?(p256dh:, auth:)
    ActiveSupport::SecurityUtils.secure_compare(p256dh_key, p256dh.to_s) &&
      ActiveSupport::SecurityUtils.secure_compare(auth_key, auth.to_s)
  end
end
