# frozen_string_literal: true

# What an invitee sees when previewing an emailed invitation link before
# accepting it.

class InvitationPreviewSerializer < ApplicationSerializer
  attributes :email, :role, :expires_at

  attribute(:group_name) { |invitation| invitation.group.name }
  attribute(:inviter_name) { |invitation| invitation.inviter.name }
  attribute(:valid, &:pending?)
end
