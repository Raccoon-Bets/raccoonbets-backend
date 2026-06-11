# frozen_string_literal: true

# RESTful controller for a {Group}'s email {Invitation}s. Admins only.
# Acceptance happens globally (outside the group scope) via
# {InvitationsController}, since invitees follow an emailed token link.

class Groups::InvitationsController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_group_admin!

  # Lists the group's pending (unaccepted, unexpired) invitations.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/invitations.json`

  def index
    @invitations = current_group.invitations.pending.order(:created_at)
    respond_with @invitations
  end

  # Creates an invitation and emails the invitee an accept link.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/invitations.json`
  #
  # Body Parameters
  # ---------------
  #
  # |               |                                                       |
  # |:--------------|:-------------------------------------------------------|
  # | `:invitation` | Parameterized Invitation attributes (`email`, `role`). |

  def create
    @invitation = current_group.invitations.create(invitation_params.merge(inviter: current_user))
    InvitationMailer.invite(@invitation).deliver_later if @invitation.persisted?
    respond_with @invitation
  end

  # Revokes a pending invitation.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/invitations/:id.json`

  def destroy
    @invitation = current_group.invitations.pending.find(params.expect(:id))
    @invitation.destroy
    respond_with @invitation
  end

  private

  def invitation_params = params.expect(invitation: %i[email role])
end
