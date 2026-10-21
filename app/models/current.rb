# frozen_string_literal: true

# Per-execution state, reset between requests and jobs.
#
# Attributes
# ----------
#
# |                     |                                                                  |
# |:--------------------|:-----------------------------------------------------------------|
# | `mail_delivery_key` | The idempotency key for the email {MailDeliveryJob} is sending.  |

class Current < ActiveSupport::CurrentAttributes
  attribute :mail_delivery_key
end
