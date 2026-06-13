# frozen_string_literal: true

# A Membership ties a {User} to a {Group}. A `requested` Membership doubles as
# a join request; admins approve it by flipping `status` to `active`, or deny
# it by destroying the row.
#
# Associations
# ------------
#
# |                   |                                                              |
# |:------------------|:-------------------------------------------------------------|
# | `user`            | The member.                                                  |
# | `group`           | The group.                                                   |
# | `invited_by`      | The {User} whose {Invitation} created this Membership, if any. |
# | `positions`       | The member's {Position}s.                                   |
# | `created_markets` | The {Market}s the member created.                            |
# | `oracle_markets`  | The {Market}s the member is the oracle for.                  |
# | `comments`        | The {Comment}s the member has written.                       |
#
# Properties
# ----------
#
# |          |                                                       |
# |:---------|:------------------------------------------------------|
# | `role`   | `member`, or `admin` (manages members and settings).  |
# | `status` | `requested` (pending join request), or `active`.      |

class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :group
  belongs_to :invited_by, class_name: "User", optional: true, inverse_of: false

  # Restricted (not destroyed) so a member with trading, ledger, or settlement
  # history cannot leave the group in a way that would silently corrupt pools
  # or the ledger. (Group deletion still works: the group cascade removes all
  # of these rows before destroying memberships.)
  has_many :positions, dependent: :restrict_with_error
  has_many :created_markets, class_name: "Market", foreign_key: :creator_id,
                             inverse_of: :creator, dependent: :restrict_with_error
  has_many :oracle_markets, class_name: "Market", foreign_key: :oracle_id,
                            inverse_of: :oracle, dependent: :restrict_with_error
  has_many :ledger_entries, dependent: :restrict_with_error
  has_many :market_events, foreign_key: :actor_membership_id,
                           inverse_of: :actor, dependent: :restrict_with_error
  has_many :comments, foreign_key: :author_membership_id,
                      inverse_of: :author, dependent: :restrict_with_error
  has_many :settlements_as_payer, class_name: "Settlement", foreign_key: :payer_membership_id,
                                   inverse_of: :payer, dependent: :restrict_with_error
  has_many :settlements_as_payee, class_name: "Settlement", foreign_key: :payee_membership_id,
                                   inverse_of: :payee, dependent: :restrict_with_error
  has_many :recorded_settlements, class_name: "Settlement", foreign_key: :recorded_by_id,
                                   inverse_of: :recorded_by, dependent: :restrict_with_error

  enum :role, {member: "member", admin: "admin"}, validate: true
  enum :status, {requested: "requested", active: "active"}, validate: true

  validates :user_id, uniqueness: {scope: :group_id}

  # @return [true, false] Whether this Membership is the group's only active
  #   admin (and so must not be demoted or removed).

  def last_admin?
    admin? && active? && group.memberships.active.admin.where.not(id:).none?
  end

  # @return [Integer] The member's realized balance: the sum of their
  #   {LedgerEntry} amounts, in minor units of the group's currency. Negative
  #   means the member owes the group.

  def balance_cents = ledger_entries.sum(:amount_cents)
end
