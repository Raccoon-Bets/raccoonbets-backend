# frozen_string_literal: true

# A short-lived browser handoff carrying a client's validated OAuth
# authorization parameters to the website's consent screen. The first member
# to view it claims it, and deciding it consumes it.
#
# Associations
# ------------
#
# |        |                                                  |
# |:-------|:-------------------------------------------------|
# | `user` | The {User} who claimed the request, if anyone.   |
#
# Properties
# ----------
#
# |               |                                                              |
# |:--------------|:-------------------------------------------------------------|
# | `identifier`  | The random, URL-safe id used in the consent URL.             |
# | `parameters`  | The validated `/oauth/authorize` parameters.                 |
# | `expires_at`  | When the request can no longer be decided.                   |
# | `consumed_at` | When the member approved or denied the request, or `nil`.    |

class McpAuthorizationRequest < ApplicationRecord
  belongs_to :user, optional: true

  # @param member [User] The signed-in member.
  # @return [Boolean] Whether the request can still be decided by this member:
  #   it is undecided, unexpired, and unclaimed or claimed by them.

  def available_to?(member)
    consumed_at.nil? && expires_at.future? && (user_id.nil? || user_id == member.id)
  end
end
