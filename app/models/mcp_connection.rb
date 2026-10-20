# frozen_string_literal: true

# A member's consent for one OAuth client to use the MCP server with a fixed
# set of {Group}s and scopes. Every authorization code and token issued under
# that consent belongs to the connection, so revoking it ends all of them.
#
# Associations
# ------------
#
# |                 |                                                           |
# |:----------------|:----------------------------------------------------------|
# | `user`          | The {User} who granted access.                            |
# | `application`   | The registered OAuth client (`Doorkeeper::Application`).  |
# | `groups`        | The {Group}s the member chose to share.                   |
# | `access_tokens` | The {Oauth::AccessToken}s issued under this consent.      |
# | `access_grants` | The {Oauth::AccessGrant}s (authorization codes) issued.   |
#
# Properties
# ----------
#
# |                  |                                                                 |
# |:-----------------|:----------------------------------------------------------------|
# | `scopes`         | Space-separated granted scopes (`mcp:read`, maybe `mcp:write`). |
# | `resource`       | The MCP server URL the consent is bound to (RFC 8707).          |
# | `expires_at`     | When the consent lapses; refreshing never extends it.           |
# | `established_at` | When the client first redeemed a code for a token, or `nil`.    |
# | `revoked_at`     | When the member or the server revoked the consent, or `nil`.    |

class McpConnection < ApplicationRecord
  # How long a member's consent lasts before the client must ask again.
  LIFETIME = 30.days

  belongs_to :user
  belongs_to :application, class_name: "Doorkeeper::Application"
  has_many :mcp_connection_groups, dependent: :delete_all
  has_many :groups, through: :mcp_connection_groups
  has_many :access_tokens, class_name: "Oauth::AccessToken", dependent: :delete_all
  has_many :access_grants, class_name: "Oauth::AccessGrant", dependent: :delete_all

  # Connections a member can still use: established, unrevoked, and unexpired.
  scope :usable, -> { where.not(established_at: nil).where(revoked_at: nil, expires_at: Time.current..) }

  # @return [Boolean] Whether this consent still permits credential use: it is
  #   unrevoked and unexpired, the member's account is open, and it is bound
  #   to this server's {Mcp::Configuration.resource}.

  def active?
    revoked_at.nil? && expires_at.future? && user.open? && resource == Mcp::Configuration.resource
  end

  # @return [ActiveRecord::Relation<Group>] The consented groups that are
  #   active and where the member still holds an active membership.

  def accessible_groups
    groups.active.where(id: user.memberships.active.select(:group_id))
  end

  # Records when the first token was issued through this connection.

  def establish!
    update!(established_at: Time.current) unless established_at
  end

  # Revokes this connection and every credential issued through it atomically,
  # keeping the original revocation time if it was already revoked.

  def revoke!
    with_lock do
      now = Time.current
      update!(revoked_at: now) unless revoked_at
      access_tokens.where(revoked_at: nil).update_all(revoked_at: now)
      access_grants.where(revoked_at: nil).update_all(revoked_at: now)
    end
  end
end
