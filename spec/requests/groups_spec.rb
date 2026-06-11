# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups" do
  let(:user) { create :user }
  let(:group) { create :group, subdomain: "trash-pandas" }
  let(:admin) { create(:membership, :admin, group:).user }

  describe "POST /" do
    let(:group_params) { {name: "Trash Pandas", subdomain: "trash-pandas", currency: "USD"} }

    it "requires a logged-in user" do
      post "/groups.json", params: {group: group_params}
      expect(response).to have_http_status(:unauthorized)
    end

    context "[authenticated]" do
      before(:each) { sign_in user }

      it "creates the group and its admin membership in one transaction" do
        post "/groups.json", params: {group: group_params}

        expect(response).to be_successful
        expect(response.body).to match_json(
                                   name:             "Trash Pandas",
                                   subdomain:        "trash-pandas",
                                   currency:         "USD",
                                   min_amount_cents: 25,
                                   max_amount_cents: 2000,
                                   status:           "active",
                                   membership:       {id: Integer, role: "admin"}
                                 )

        membership = Group.find_by!(subdomain: "trash-pandas").memberships.sole
        expect(membership.user).to eql(user)
        expect(membership).to be_admin
        expect(membership).to be_active
      end

      it "handles validation errors" do
        post "/groups.json", params: {group: group_params.merge(subdomain: "www")}

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to match_json(errors: {subdomain: [String]})
        expect(Group.count).to eq(0)
      end
    end
  end

  describe "GET /availability" do
    before(:each) { sign_in user }

    it "reports reserved, taken, and malformed subdomains as unavailable" do
      group # create trash-pandas

      get "/groups/availability.json", params: {subdomain: "www"}
      expect(response.body).to match_json(subdomain: "www", available: false)

      get "/groups/availability.json", params: {subdomain: "TRASH-Pandas"}
      expect(response.body).to match_json(subdomain: "trash-pandas", available: false)

      get "/groups/availability.json", params: {subdomain: "-bad-"}
      expect(response.body).to match_json(subdomain: "-bad-", available: false)
    end

    it "reports unclaimed subdomains as available" do
      get "/groups/availability.json", params: {subdomain: "fresh-den"}
      expect(response.body).to match_json(subdomain: "fresh-den", available: true)
    end
  end

  describe "GET /:group_id" do
    it "requires a logged-in user" do
      get "/groups/#{group.to_param}.json"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the full group to active members" do
      sign_in admin
      get "/groups/#{group.to_param}.json"

      expect(response).to be_successful
      expect(response.body).to match_json(
                                 name:             String,
                                 subdomain:        "trash-pandas",
                                 currency:         "USD",
                                 min_amount_cents: 25,
                                 max_amount_cents: 2000,
                                 status:           "active",
                                 membership:       {id: Integer, role: "admin"}
                               )
    end

    it "returns only a minimal preview to non-members" do
      admin # ensure the group has a member
      create :membership, :requested, group:, user: user
      sign_in user

      get "/groups/#{group.to_param}.json"

      expect(response).to be_successful
      expect(response.body).to match_json(
                                 name:           String,
                                 subdomain:      "trash-pandas",
                                 member_count:   1,
                                 join_requested: true
                               )
    end

    it "returns 404 for suspended groups" do
      group.update! status: :suspended
      sign_in admin

      get "/groups/#{group.to_param}.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /:group_id" do
    let(:member) { create(:membership, group:).user }

    it "requires a group admin" do
      sign_in member
      patch "/groups/#{group.to_param}.json", params: {group: {name: "New Name"}}
      expect(response).to have_http_status(:forbidden)
    end

    context "[as admin]" do
      before(:each) { sign_in admin }

      it "updates name and amount limits but never subdomain or currency" do
        patch "/groups/#{group.to_param}.json",
              params: {group: {name:             "Renamed Den",
                               min_amount_cents: 100,
                               max_amount_cents: 5000,
                               subdomain:        "hijacked",
                               currency:         "EUR"}}

        expect(response).to be_successful
        group.reload
        expect(group.name).to eq("Renamed Den")
        expect(group.min_amount_cents).to eq(100)
        expect(group.max_amount_cents).to eq(5000)
        expect(group.subdomain).to eq("trash-pandas")
        expect(group.currency).to eq("USD")
      end

      it "handles validation errors" do
        patch "/groups/#{group.to_param}.json",
              params: {group: {min_amount_cents: 5000, max_amount_cents: 100}}

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to match_json(errors: {max_amount_cents: [String]})
      end
    end
  end
end
