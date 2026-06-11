# frozen_string_literal: true

# Responds to incoming requests by rendering the raw contents of the last email
# sent by the test mailer. Mounted only in the Cypress environment.
#
# This middleware must be mounted at a specific route, not added to the
# middleware chain.

class Cypress::LastEmail

  # @private
  def call(_env)
    if (mail = last_email)
      email_response(mail)
    else
      no_email_response
    end
  end

  private

  def no_email_response = [404, {"Content-Type" => "text-plain"}, ["No emails yet"]]

  def email_response(mail) = [200, {"Content-Type" => "text/plain"}, [mail.to_s]]

  def last_email = ActionMailer::Base.deliveries.last
end
