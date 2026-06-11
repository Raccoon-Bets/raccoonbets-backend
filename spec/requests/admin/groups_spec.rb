# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/admin/groups" do
  let(:superadmin) { create :user, :superadmin }
  let(:group) { create :group, subdomain: "trash-pandas" }

  describe "[superadmin gate]" do
    it "rejects regular users — even the group's own admin" do
      group_admin = create(:membership, :admin, group:).user
      sign_in group_admin

      get "/admin/groups.json"
      expect(response).to have_http_status(:forbidden)

      patch "/admin/groups/#{group.to_param}.json", params: {group: {status: "suspended"}}
      expect(response).to have_http_status(:forbidden)

      delete "/admin/groups/#{group.to_param}.json"
      expect(response).to have_http_status(:forbidden)
      expect(group.reload).to be_active
    end
  end

  context "[as superadmin]" do
    before(:each) { sign_in superadmin }

    it "lists all groups, including suspended ones" do
      group
      create :group, :suspended, subdomain: "banned-den"

      get "/admin/groups.json"

      expect(response).to be_successful
      expect(response.body).to match_json([
          hash_including(subdomain: "banned-den", status: "suspended"),
          hash_including(subdomain: "trash-pandas", status: "active")
      ])
    end

    it "suspends and reinstates groups" do
      patch "/admin/groups/#{group.to_param}.json", params: {group: {status: "suspended"}}

      expect(response).to be_successful
      expect(group.reload).to be_suspended
    end

    it "renames a group's subdomain" do
      patch "/admin/groups/#{group.to_param}.json", params: {group: {subdomain: "better-name"}}

      expect(response).to be_successful
      expect(group.reload.subdomain).to eq("better-name")
    end

    it "deletes a group, cascading over its ledger, settlements, and markets" do
      market = create(:market, group:)
      create(:position, market:, outcome: market.outcomes.first, amount_cents: 100)
      create(:position, market:, outcome: market.outcomes.second, amount_cents: 100)
      market.update_column :locks_at, 1.hour.ago # rubocop:disable Rails/SkipsModelValidations
      Markets::Resolver.resolve market, market.outcomes.first, market.oracle
      create(:settlement, group:).void!

      delete "/admin/groups/#{group.to_param}.json"

      expect(response).to be_successful
      expect { group.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(LedgerEntry.where(group_id: group.id)).to be_empty
      expect(Settlement.where(group_id: group.id)).to be_empty
    end
  end
end
