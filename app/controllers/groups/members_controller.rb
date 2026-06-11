# frozen_string_literal: true

# RESTful controller for a {Group}'s active {Membership}s: the roster, role
# changes, removal, and self-leave. A group must always keep at least one
# active admin, so the last admin can be neither demoted nor removed.

class Groups::MembersController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_membership!, only: :index
  before_action :require_group_admin!, only: :update
  before_action :find_membership, only: %i[update destroy]

  # Lists the group's active members. Members only.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/members.json`

  def index
    @memberships = current_group.memberships.active.includes(:user).order(:created_at)
    respond_with @memberships
  end

  # Changes a member's role (`member` ↔ `admin`). Admins only. The group's
  # last admin cannot be demoted.
  #
  # Routes
  # ------
  #
  # * `PATCH /groups/:group_id/members/:id.json`
  #
  # Body Parameters
  # ---------------
  #
  # |               |                                            |
  # |:--------------|:--------------------------------------------|
  # | `:membership` | Parameterized Membership `role` attribute. |

  def update
    return render_last_admin_error if demoting_last_admin?

    @membership.update membership_params
    respond_with @membership
  end

  # Removes a member: admins can remove anyone, and any member can remove
  # themselves (leave the group). The group's last admin cannot be removed.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/members/:id.json`

  def destroy
    return require_group_admin! unless admin_or_self?
    return render_last_admin_error if @membership.last_admin?

    @membership.destroy
    respond_with @membership
  end

  private

  def find_membership
    @membership = current_group.memberships.active.find(params.expect(:id))
  end

  def membership_params = params.expect(membership: %i[role])

  def demoting_last_admin?
    @membership.last_admin? && membership_params[:role] != "admin"
  end

  def admin_or_self?
    current_membership&.admin? || @membership == current_membership
  end

  def render_last_admin_error
    render json:   {error: I18n.t("groups.members.errors.last_admin")},
           status: :unprocessable_content
  end
end
