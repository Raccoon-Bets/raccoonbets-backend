# frozen_string_literal: true

# A User is the global account for Raccoon Bets. Users have one account
# site-wide and can belong to many groups.
#
# Associations
# ------------
#
# |                 |                                                 |
# |:----------------|:------------------------------------------------|
# | `webauthn_keys` | Registered passkey credentials.                 |
# | `identities`    | Linked external logins (Google, Apple).         |
# | `memberships`   | The {Membership}s tying this user to {Group}s.  |
# | `groups`        | The {Group}s this user belongs to (any status). |
#
# Properties
# ----------
#
# |                   |                                                                                     |
# |:------------------|:------------------------------------------------------------------------------------|
# | `name`            | The user's display name.                                                            |
# | `email`           | The user's email, used to uniquely identify the user and for forgotten passwords.   |
# | `locale`          | The user's preferred UI/email language as a BCP-47 tag, or `nil` for default.       |
# | `superadmin`      | Whether the user can administer all groups site-wide (squatting control, suspends). |
# | `venmo_handle`    | The user's Venmo handle, for settle-up payment links.                               |
# | `paypal_handle`   | The user's PayPal.me handle, for settle-up payment links.                           |
# | `cashapp_cashtag` | The user's Cash App cashtag, for settle-up payment links.                           |

class User < ApplicationRecord
  include Rodauth::Rails.model

  # The locales the app is translated into. Mirrors the frontend's `SUPPORTED_LOCALES`.
  SUPPORTED_LOCALES = %w[en].freeze

  validates :locale, inclusion: {in: SUPPORTED_LOCALES}, allow_nil: true

  has_many :webauthn_keys, class_name:  "AccountWebauthnKey",
                           foreign_key: :account_id,
                           dependent:   :delete_all,
                           inverse_of:  :user

  has_many :identities, class_name: "AccountIdentity",
                        dependent:  :delete_all,
                        inverse_of: :user

  has_many :memberships, dependent: :destroy
  has_many :groups, through: :memberships
  has_many :push_subscriptions, dependent: :delete_all

  validates :name,
            presence: true,
            length:   {maximum: 200}
  validates :email,
            presence:   true,
            uniqueness: {case_sensitive: false},
            format:     {with: /\A[^@\s]+@[^@\s]+\z/}
  validates :venmo_handle, :paypal_handle, :cashapp_cashtag,
            length:    {maximum: 100},
            allow_nil: true

  # @return [NotificationPreferences] the per-event x channel notification prefs.
  def notification_preferences_object
    NotificationPreferences.new(notification_preferences)
  end
end
