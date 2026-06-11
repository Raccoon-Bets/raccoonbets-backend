# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/members" do
  let(:group) { create :group }
  let(:admin_membership) { create :membership, :admin, group: }
  let(:admin) { admin_membership.user }
  let(:member_membership) { create :membership, group: }
  let(:member) { member_membership.user }
  let(:outsider) { create :user }

  describe "GET /" do
    it "rejects non-members" do
      sign_in outsider
      get "/groups/#{group.to_param}/members.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "lists active members to members" do
      admin_membership
      sign_in member
      get "/groups/#{group.to_param}/members.json"

      expect(response).to be_successful
      expect(response.body).to match_json([{
          id:         Integer,
          role:       String,
          status:     "active",
          created_at: String,
          user:       {id: Integer, name: String}
      }] * 2)
    end
  end

  describe "PATCH /:id" do
    it "requires a group admin" do
      sign_in member
      patch "/groups/#{group.to_param}/members/#{admin_membership.id}.json",
            params: {membership: {role: "member"}}
      expect(response).to have_http_status(:forbidden)
    end

    context "[as admin]" do
      before(:each) { sign_in admin }

      it "changes a member's role" do
        patch "/groups/#{group.to_param}/members/#{member_membership.id}.json",
              params: {membership: {role: "admin"}}

        expect(response).to be_successful
        expect(member_membership.reload).to be_admin
      end

      it "refuses to demote the last admin" do
        patch "/groups/#{group.to_param}/members/#{admin_membership.id}.json",
              params: {membership: {role: "member"}}

        expect(response).to have_http_status(:unprocessable_content)
        expect(admin_membership.reload).to be_admin
      end
    end
  end

  describe "DELETE /:id" do
    it "does not let a member remove someone else" do
      other = create(:membership, group:)
      sign_in member

      delete "/groups/#{group.to_param}/members/#{other.id}.json"
      expect(response).to have_http_status(:forbidden)
      expect(other.reload).to be_persisted
    end

    it "lets a member leave the group" do
      admin_membership
      sign_in member

      delete "/groups/#{group.to_param}/members/#{member_membership.id}.json"

      expect(response).to be_successful
      expect { member_membership.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "lets an admin remove a member" do
      sign_in admin
      delete "/groups/#{group.to_param}/members/#{member_membership.id}.json"

      expect(response).to be_successful
      expect { member_membership.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "refuses to remove the last admin" do
      sign_in admin
      delete "/groups/#{group.to_param}/members/#{admin_membership.id}.json"

      expect(response).to have_http_status(:unprocessable_content)
      expect(admin_membership.reload).to be_persisted
    end
  end
end
