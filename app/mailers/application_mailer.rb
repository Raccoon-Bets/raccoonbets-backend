# frozen_string_literal: true

# @abstract
#
# The abstract superclass for all Raccoon Bets mailers.

class ApplicationMailer < ActionMailer::Base
  default from: "donotreply@raccoonbets.org"
  layout "mailer"

  private

  # Sends the mail in the recipient's stored locale (emails ignore the
  # request's negotiated locale).
  #
  # @param user [User] the recipient.
  # @param subject_key [String] the i18n key for the subject line.
  # @param subject_args [Hash] interpolations for the subject line.
  def mail_localized(user, subject_key, **subject_args)
    I18n.with_locale(user.locale) do
      mail to: user.email, subject: I18n.t(subject_key, **subject_args)
    end
  end
end
