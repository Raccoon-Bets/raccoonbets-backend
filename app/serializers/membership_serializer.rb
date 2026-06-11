# frozen_string_literal: true

class MembershipSerializer < ApplicationSerializer
  attributes :id, :role, :status, :created_at

  attribute :user do |membership|
    {id: membership.user_id, name: membership.user.name}
  end
end
