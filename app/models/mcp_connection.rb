# frozen_string_literal: true

# A member's consent for one OAuth client, a fixed group set, and scopes.
class McpConnection < ApplicationRecord
  belongs_to :user
  belongs_to :application, class_name: "Doorkeeper::Application"
  has_many :mcp_connection_groups, dependent: :delete_all
  has_many :groups, through: :mcp_connection_groups
  has_many :access_tokens, class_name: "Oauth::AccessToken", dependent: :delete_all
  has_many :access_grants, class_name: "Oauth::AccessGrant", dependent: :delete_all

  # @return [Boolean] whether this consent still permits credential use.
  def active?
    revoked_at.nil? && expires_at.future? && user.status_id == 2 && resource == Mcp::Configuration.resource
  end

  # @return [ActiveRecord::Relation<Group>] consented groups with current membership.
  def accessible_groups
    groups.active.where(id: user.memberships.active.select(:group_id))
  end

  # Revokes this connection and every credential issued through it atomically.
  def revoke!
    with_lock do
      update!(revoked_at: Time.current)
      access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
      access_grants.where(revoked_at: nil).update_all(revoked_at: Time.current)
    end
  end
end
