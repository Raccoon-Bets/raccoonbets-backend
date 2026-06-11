# frozen_string_literal: true

# @abstract
#
# The abstract superclass for all Raccoon Bets mailers.

class ApplicationMailer < ActionMailer::Base
  default from: "donotreply@raccoonbets.org"
  layout "mailer"
end
