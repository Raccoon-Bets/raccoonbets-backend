# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/settle_up" do
  let(:group) { create :group }
  let(:alice) { create :membership, group: }
  let(:bob) { create :membership, group: }
  let(:path) { "/groups/#{group.to_param}/settle_up.json" }

  it "rejects non-members" do
    sign_in create(:user)
    get path
    expect(response).to have_http_status(:forbidden)
  end

  it "suggests transfers with the payee's payment handles and a payment note" do
    alice.user.update! venmo_handle: "alice-pays", cashapp_cashtag: "$alice"
    create(:settlement, group:, payer: alice, payee: bob, amount_cents: 400)

    sign_in bob.user
    get path

    expect(response).to be_successful
    expect(response.body).to match_json(
        currency:  "USD",
        note:      "Raccoon Bets — #{group.name}",
        transfers: [{
            payer_membership_id: bob.id,
            payee_membership_id: alice.id,
            amount_cents:        400,
            payee:               {
                membership_id:   alice.id,
                name:            alice.user.name,
                venmo_handle:    "alice-pays",
                paypal_handle:   nil,
                cashapp_cashtag: "alice"
            }
        }]
      )
  end
end
