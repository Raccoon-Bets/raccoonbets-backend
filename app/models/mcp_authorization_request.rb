# frozen_string_literal: true

# Short-lived browser handoff containing validated OAuth request parameters.
class McpAuthorizationRequest < ApplicationRecord
  belongs_to :user, optional: true

  # @return [Boolean] whether the request can still be decided by this member.
  def available_to?(member)
    consumed_at.nil? && expires_at.future? && (user_id.nil? || user_id == member.id)
  end
end
