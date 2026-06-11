# frozen_string_literal: true

# Scopes a controller to the {Group} named by the `:group_id` path parameter
# (the group's subdomain slug). All group-scoped lookups must flow through
# {#current_group}'s associations so cross-tenant access is structurally
# impossible.
#
# Missing and suspended groups both render 404, so outsiders cannot
# distinguish a suspended group from one that never existed.

module GroupScoping
  extend ActiveSupport::Concern

  private

  # @return [Group] The active Group for the request's `:group_id` slug.
  # @raise [ActiveRecord::RecordNotFound] If no active group matches (404).

  def current_group
    @current_group ||= Group.active.find_by!(subdomain: params.expect(:group_id))
  end

  # @return [Membership, nil] The current user's active Membership in
  #   {#current_group}, if any.

  def current_membership
    return @current_membership if defined?(@current_membership)

    @current_membership = (current_group.memberships.active.find_by(user: current_user) if current_user)
  end

  def require_membership!
    return if current_membership

    render json:   {error: I18n.t("group_scoping.errors.not_a_member")},
           status: :forbidden
  end

  def require_group_admin!
    return if current_membership&.admin?

    render json:   {error: I18n.t("group_scoping.errors.not_an_admin")},
           status: :forbidden
  end

  # Renders 403 unless the current member is a group admin or the oracle of
  # the market in `@market` — set `@market` in an earlier before_action.
  def require_oracle_or_admin!
    return if current_membership && (current_membership.admin? || current_membership.id == @market.oracle_id)

    render json:   {error: I18n.t("group_scoping.errors.not_oracle_or_admin")},
           status: :forbidden
  end
end
