# frozen_string_literal: true

# Controller for previewing and accepting {Invitation}s by emailed token.
# These routes are global (not group-scoped) because invitees follow the
# emailed link before they belong to the group. Admins manage a group's
# invitations through {Groups::InvitationsController}.

class InvitationsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_invitation

  # Previews an invitation: the group and inviter names and whether the
  # invitation can still be accepted.
  #
  # Routes
  # ------
  #
  # * `GET /invitations/:token.json`

  def show
    respond_with @invitation
  end

  # Accepts an invitation, creating an active {Membership} with the
  # invitation's role (or activating the current user's pending join request).
  # If the current user is already an active member the request succeeds
  # without changes. Expired or already-accepted invitations render 410 Gone.
  #
  # Routes
  # ------
  #
  # * `POST /invitations/:token/accept.json`

  def accept
    return render_gone unless @invitation.pending? || already_member?

    newly_joined = !already_member?
    @membership  = find_or_activate_membership
    @group       = @invitation.group
    GroupChannel.broadcast_event @group, :member_joined if newly_joined
    respond_with @group
  end

  private

  def find_invitation
    @invitation = Invitation.find_by!(token: params.expect(:token))
  end

  def already_member? = membership_for_current_user&.active? || false

  def membership_for_current_user
    return @membership_for_current_user if defined?(@membership_for_current_user)

    @membership_for_current_user = @invitation.group.memberships.find_by(user: current_user)
  end

  def find_or_activate_membership
    membership = membership_for_current_user ||
      @invitation.group.memberships.new(user: current_user, role: @invitation.role)
    Invitation.transaction do
      unless membership.persisted? && membership.active?
        membership.update!(status: :active, role: @invitation.role, invited_by: @invitation.inviter)
      end
      @invitation.update!(accepted_at: Time.current) unless @invitation.accepted?
    end
    membership
  end

  def render_gone
    render json:   {error: I18n.t("invitations.errors.no_longer_valid")},
           status: :gone
  end
end
