# frozen_string_literal: true

# Full Group representation for members (and superadmins). Pass a
# `:membership` param to embed the viewer's own membership.

class GroupSerializer < ApplicationSerializer
  attributes :name, :subdomain, :currency, :min_amount_cents, :max_amount_cents, :status

  attribute :membership, if: proc { params[:membership] } do
    {id: params[:membership].id, role: params[:membership].role}
  end
end
