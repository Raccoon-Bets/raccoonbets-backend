# frozen_string_literal: true

# Invitation representation for group admins. The token is deliberately
# omitted: it only ever travels in the invitee's email.

class InvitationSerializer < ApplicationSerializer
  attributes :id, :email, :role, :expires_at, :created_at
end
