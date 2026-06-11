# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/balances" do
  let(:group) { create :group }
  let(:alice) { create :membership, group: }
  let(:bob) { create :membership, group: }
  let(:path) { "/groups/#{group.to_param}/balances.json" }

  it "rejects non-members" do
    sign_in create(:user)
    get path
    expect(response).to have_http_status(:forbidden)
  end

  it "lists every active member's balance, zero balances included" do
    bystander = create(:membership, group:)
    create(:settlement, group:, payer: alice, payee: bob, amount_cents: 150)

    sign_in alice.user
    get path

    expect(response).to be_successful
    expect(response.body).to match_json(
        currency: "USD",
        balances: [
            {membership_id: alice.id, name: alice.user.name, balance_cents: 150},
            {membership_id: bystander.id, name: bystander.user.name, balance_cents: 0},
            {membership_id: bob.id, name: bob.user.name, balance_cents: -150}
        ]
      )
  end
end
