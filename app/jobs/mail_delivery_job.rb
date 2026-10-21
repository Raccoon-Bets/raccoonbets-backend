# frozen_string_literal: true

# Delivers `deliver_later` emails with an idempotency key derived from the job
# ID, which every retry of the job shares. If a delivery fails after the email
# provider accepted it, the retry is recognized as the same email instead of
# sending a duplicate.

class MailDeliveryJob < ActionMailer::MailDeliveryJob
  around_perform do |job, block|
    Current.set(mail_delivery_key: "mail-delivery/#{job.job_id}", &block)
  end
end
