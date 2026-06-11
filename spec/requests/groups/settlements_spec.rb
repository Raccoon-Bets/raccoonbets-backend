# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/settlements" do
  let(:group) { create :group }
  let(:admin) { create :membership, :admin, group: }
  let(:alice) { create :membership, group: }
  let(:bob) { create :membership, group: }
  let(:path) { "/groups/#{group.to_param}/settlements.json" }

  describe "GET /" do
    it "rejects non-members" do
      sign_in create(:user)
      get path
      expect(response).to have_http_status(:forbidden)
    end

    it "lists settlements with a voided flag" do
      create(:settlement, group:, payer: alice, payee: bob, amount_cents: 100)
      create(:settlement, group:, payer: bob, payee: alice, amount_cents: 200).void!

      sign_in alice.user
      get path

      expect(response).to be_successful
      expect(response.parsed_body.map { it.values_at("amount_cents", "voided") }).
          to contain_exactly([100, false], [200, true])
    end
  end

  describe "POST /" do
    it "records a settlement the member is party to, defaulting the payer to themselves" do
      sign_in alice.user
      post path, params: {settlement: {payee_membership_id: bob.id, amount_cents: 300, payment_method: "venmo"}}

      expect(response).to be_successful
      settlement = group.settlements.sole
      expect(settlement.payer).to eq(alice)
      expect(settlement.payee).to eq(bob)
      expect(settlement.recorded_by).to eq(alice)
      expect(alice.balance_cents).to eq(300)
      expect(bob.balance_cents).to eq(-300)
      expect(group).to have_zero_sum_ledger
    end

    it "rejects recording a settlement between two other members" do
      carol = create(:membership, group:)
      sign_in carol.user

      post path, params: {settlement: {payer_membership_id: alice.id, payee_membership_id: bob.id,
                                       amount_cents: 300, payment_method: "cash"}}

      expect(response).to have_http_status(:forbidden)
      expect(group.settlements).to be_empty
    end

    it "lets an admin record a settlement between any two members" do
      sign_in admin.user
      post path, params: {settlement: {payer_membership_id: alice.id, payee_membership_id: bob.id,
                                       amount_cents: 300, payment_method: "cash"}}

      expect(response).to be_successful
      expect(group.settlements.sole.recorded_by).to eq(admin)
    end

    it "rejects a settlement from a member to themselves" do
      sign_in alice.user
      post path, params: {settlement: {payee_membership_id: alice.id, amount_cents: 300, payment_method: "cash"}}

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /:id" do
    let(:settlement) { create :settlement, group:, payer: alice, payee: bob, amount_cents: 250 }

    it "rejects members who are not party to the settlement" do
      carol = create(:membership, group:)
      sign_in carol.user

      delete "#{path.delete_suffix(".json")}/#{settlement.id}.json"

      expect(response).to have_http_status(:forbidden)
      expect(settlement.reload).not_to be_voided
    end

    it "lets a party void, reversing the ledger entries without deleting anything" do
      sign_in bob.user
      delete "#{path.delete_suffix(".json")}/#{settlement.id}.json"

      expect(response).to be_successful
      expect(response.parsed_body).to include("voided" => true)
      expect(settlement.reload).to be_voided
      expect(settlement.ledger_entries.count).to eq(4)
      expect(alice.balance_cents).to eq(0)
      expect(bob.balance_cents).to eq(0)
      expect(group).to have_zero_sum_ledger
    end

    it "rejects voiding an already-voided settlement" do
      settlement.void!
      sign_in alice.user

      delete "#{path.delete_suffix(".json")}/#{settlement.id}.json"

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
