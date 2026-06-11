# frozen_string_literal: true

# Controller for join requests: `requested` {Membership}s that group admins
# approve (flipping them to `active`) or deny (destroying them). Requesters
# can withdraw their own pending request.

class Groups::JoinRequestsController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_group_admin!, only: %i[index approve]
  before_action :find_join_request, only: %i[approve destroy]

  # Lists the group's pending join requests. Admins only.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/join_requests.json`

  def index
    @memberships = current_group.memberships.requested.includes(:user).order(:created_at)
    respond_with @memberships
  end

  # Creates a join request (a `requested` Membership) for the current user.
  # Fails with a validation error if the user already has a membership or
  # pending request.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/join_requests.json`

  def create
    @membership = current_group.memberships.create(user: current_user, role: :member, status: :requested)
    respond_with @membership
  end

  # Approves a join request, activating the membership. Admins only.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/join_requests/:id/approve.json`

  def approve
    GroupChannel.broadcast_event current_group, :member_joined if @membership.update(status: :active)
    respond_with @membership
  end

  # Denies a join request (admins), or withdraws it (the requester). Destroys
  # the requested Membership.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/join_requests/:id.json`

  def destroy
    return require_group_admin! unless admin_or_requester?

    @membership.destroy
    respond_with @membership
  end

  private

  def find_join_request
    @membership = current_group.memberships.requested.find(params.expect(:id))
  end

  def admin_or_requester?
    current_membership&.admin? || @membership.user == current_user
  end
end
