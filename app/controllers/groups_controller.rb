# frozen_string_literal: true

# RESTful controller for creating, listing, and managing {Group}s.
#
# Members see the full group representation (settings plus their own
# membership); everyone else — authenticated or not — sees a minimal preview
# suitable for a join page. Suspended or unknown groups render 404.

class GroupsController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!, except: :show
  before_action :require_group_admin!, only: :update

  # Lists the groups the current user is an active member of.
  #
  # Routes
  # ------
  #
  # * `GET /groups.json`

  def index
    @groups = current_user.groups.merge(Membership.active).active.order(:name)
    respond_with @groups
  end

  # Displays a group. Active members receive the full representation
  # (settings and their own membership); everyone else — including logged-out
  # visitors — receives a minimal preview (name, member count, whether the
  # viewer has a pending join request).
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id.json`
  #
  # Path Parameters
  # ---------------
  #
  # |            |                          |
  # |:-----------|:-------------------------|
  # | `group_id` | The subdomain of a Group. |

  def show
    @group      = current_group
    @membership = current_membership
    @join_requested = current_user.present? && @membership.nil? &&
                      current_group.memberships.requested.exists?(user: current_user)
    respond_with @group
  end

  # Creates a Group and makes the current user its first admin, in one
  # transaction.
  #
  # Routes
  # ------
  #
  # * `POST /groups.json`
  #
  # Body Parameters
  # ---------------
  #
  # |          |                                                                                          |
  # |:---------|:-----------------------------------------------------------------------------------------|
  # | `:group` | Parameterized Group attributes (`name`, `subdomain`, `currency`, optional amount limits). |

  def create
    @group      = Group.new(create_params)
    @membership = @group.memberships.build(user: current_user, role: :admin, status: :active)
    @group.save # persists the group and the admin membership in one transaction
    respond_with @group
  end

  # Updates a group's settings. Admins only. The subdomain and currency cannot
  # be changed here (subdomain renames are a superadmin operation; currency is
  # immutable).
  #
  # Routes
  # ------
  #
  # * `PATCH /groups/:group_id.json`
  #
  # Path Parameters
  # ---------------
  #
  # |            |                          |
  # |:-----------|:-------------------------|
  # | `group_id` | The subdomain of a Group. |
  #
  # Body Parameters
  # ---------------
  #
  # |          |                                                                |
  # |:---------|:----------------------------------------------------------------|
  # | `:group` | Parameterized Group attributes (`name`, `min/max_amount_cents`). |

  def update
    @group      = current_group
    @membership = current_membership
    @group.update update_params
    respond_with @group
  end

  # Reports whether a subdomain is available for a new group, considering
  # format, the reserved list, and existing groups (case-insensitively).
  #
  # Routes
  # ------
  #
  # * `GET /groups/availability.json?subdomain=...`

  def availability
    subdomain = params.expect(:subdomain).to_s.strip.downcase
    render json: {subdomain:, available: available?(subdomain)}
  end

  private

  def create_params
    params.expect(group: %i[name subdomain currency min_amount_cents max_amount_cents])
  end

  def update_params
    params.expect(group: %i[name min_amount_cents max_amount_cents])
  end

  def available?(subdomain)
    Group::SUBDOMAIN_FORMAT.match?(subdomain) &&
      Group::RESERVED_SUBDOMAINS.exclude?(subdomain) &&
      !Group.exists?(["lower(subdomain) = ?", subdomain])
  end
end
