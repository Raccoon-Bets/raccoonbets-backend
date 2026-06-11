# frozen_string_literal: true

# Superadmin controller for site-wide {Group} administration: squatting
# control (subdomain renames), suspension/reinstatement, and deletion.
# API-only in v1; there is no admin UI yet.

class Admin::GroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_superadmin!
  before_action :find_group, only: %i[update destroy]

  # Lists all groups, including suspended ones.
  #
  # Routes
  # ------
  #
  # * `GET /admin/groups.json`

  def index
    @groups = Group.order(:subdomain)
    respond_with @groups
  end

  # Updates a group: rename it or its subdomain, or suspend/reinstate it via
  # `status`.
  #
  # Routes
  # ------
  #
  # * `PATCH /admin/groups/:id.json`
  #
  # Path Parameters
  # ---------------
  #
  # |      |                          |
  # |:-----|:-------------------------|
  # | `id` | The subdomain of a Group. |
  #
  # Body Parameters
  # ---------------
  #
  # |          |                                                            |
  # |:---------|:------------------------------------------------------------|
  # | `:group` | Parameterized Group attributes (`name`, `subdomain`, `status`). |

  def update
    @group.update group_params
    respond_with @group
  end

  # Deletes a group and all its memberships and invitations.
  #
  # Routes
  # ------
  #
  # * `DELETE /admin/groups/:id.json`

  def destroy
    @group.destroy
    respond_with @group
  end

  private

  def find_group
    @group = Group.find_by!(subdomain: params.expect(:id))
  end

  def group_params = params.expect(group: %i[name subdomain status])
end
