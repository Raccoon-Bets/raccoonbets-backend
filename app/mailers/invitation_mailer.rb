# frozen_string_literal: true

# Sends group {Invitation} emails with a tokenized accept link. Invitees may
# not have accounts yet, so emails use the default locale.

class InvitationMailer < ApplicationMailer
  # Emails the invitee a link to accept the given invitation.
  #
  # @param [Invitation] invitation The invitation to deliver.
  # @return [Mail::Message] The invitation email.

  def invite(invitation)
    @invitation = invitation
    @group      = invitation.group
    @inviter    = invitation.inviter
    @link       = "#{Rails.application.config.urls.frontend}/invitations/#{invitation.token}"

    mail to:      invitation.email,
         subject: I18n.t("invitation_mailer.invite.subject", group: @group.name)
  end
end
