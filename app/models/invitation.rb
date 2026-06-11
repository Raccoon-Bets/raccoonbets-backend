# frozen_string_literal: true

# An Invitation is an email invite into a {Group}, sent by a group admin. The
# recipient follows an emailed link containing `token` and accepts it once
# authenticated, which creates an active {Membership} with the invitation's
# role.
#
# Associations
# ------------
#
# |           |                                  |
# |:----------|:---------------------------------|
# | `group`   | The group being invited into.    |
# | `inviter` | The {User} who sent the invite.  |
#
# Properties
# ----------
#
# |               |                                                            |
# |:--------------|:-----------------------------------------------------------|
# | `email`       | The invitee's email address.                               |
# | `role`        | The {Membership} role granted on acceptance.               |
# | `token`       | The unique URL-safe token in the emailed accept link.      |
# | `accepted_at` | When the invitation was accepted, or `nil` while open.     |
# | `expires_at`  | When the invitation lapses (14 days from creation by default). |

class Invitation < ApplicationRecord
  # How long an invitation remains acceptable.
  VALIDITY_PERIOD = 14.days

  belongs_to :group
  belongs_to :inviter, class_name: "User", inverse_of: false

  enum :role, {member: "member", admin: "admin"}, validate: true

  has_secure_token

  attribute :expires_at, default: -> { VALIDITY_PERIOD.from_now }

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email,
            presence: true,
            format:   {with: /\A[^@\s]+@[^@\s]+\z/, allow_blank: true}
  validates :email,
            uniqueness: {scope: :group_id, conditions: -> { where(accepted_at: nil) }},
            if:         -> { accepted_at.nil? }
  validates :expires_at, presence: true

  scope :pending, -> { where(accepted_at: nil).where(expires_at: Time.current...) }

  # @return [true, false] Whether the invitation has been accepted.
  def accepted? = accepted_at.present?

  # @return [true, false] Whether the invitation has lapsed unaccepted.
  def expired? = !accepted? && expires_at.past?

  # @return [true, false] Whether the invitation can still be accepted.
  def pending? = !accepted? && !expired?
end
