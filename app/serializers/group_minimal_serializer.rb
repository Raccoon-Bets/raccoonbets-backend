# frozen_string_literal: true

# Minimal Group preview for authenticated non-members (join page): no
# settings, just enough to decide whether to request to join. Pass a
# `:join_requested` param to indicate the viewer's pending join request.

class GroupMinimalSerializer < ApplicationSerializer
  attributes :name, :subdomain

  attribute :member_count do |group|
    group.memberships.active.count
  end

  attribute :join_requested do
    params.fetch(:join_requested, false)
  end
end
