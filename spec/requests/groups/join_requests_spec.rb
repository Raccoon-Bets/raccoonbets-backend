# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/join_requests" do
  let(:group) { create :group }
  let(:admin_membership) { create :membership, :admin, group: }
  let(:admin) { admin_membership.user }
  let(:member) { create(:membership, group:).user }
  let(:requester) { create :user }
  let(:join_request) { create :membership, :requested, group:, user: requester }

  describe "POST /" do
    it "creates a join request for a non-member" do
      sign_in requester
      post "/groups/#{group.to_param}/join_requests.json"

      expect(response).to be_successful
      membership = group.memberships.find_by!(user: requester)
      expect(membership).to be_requested
      expect(membership).to be_member
    end

    it "rejects users who already have a membership" do
      sign_in member
      post "/groups/#{group.to_param}/join_requests.json"

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match_json(errors: {user_id: [String]})
    end

    it "returns 404 for suspended groups" do
      group.update! status: :suspended
      sign_in requester

      post "/groups/#{group.to_param}/join_requests.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /" do
    it "requires a group admin" do
      sign_in member
      get "/groups/#{group.to_param}/join_requests.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "lists pending join requests to admins" do
      join_request
      sign_in admin

      get "/groups/#{group.to_param}/join_requests.json"

      expect(response).to be_successful
      expect(response.body).to match_json([{
                                              id:         join_request.id,
                                              role:       "member",
                                              status:     "requested",
                                              created_at: String,
                                              user:       {id: requester.id, name: requester.name}
                                          }])
    end
  end

  describe "POST /:id/approve" do
    it "requires a group admin" do
      sign_in member
      post "/groups/#{group.to_param}/join_requests/#{join_request.id}/approve.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "activates the membership" do
      sign_in admin
      post "/groups/#{group.to_param}/join_requests/#{join_request.id}/approve.json"

      expect(response).to be_successful
      expect(join_request.reload).to be_active
    end
  end

  describe "DELETE /:id" do
    it "does not let unrelated users deny a request" do
      sign_in member
      delete "/groups/#{group.to_param}/join_requests/#{join_request.id}.json"

      expect(response).to have_http_status(:forbidden)
      expect(join_request.reload).to be_persisted
    end

    it "lets an admin deny a request" do
      sign_in admin
      delete "/groups/#{group.to_param}/join_requests/#{join_request.id}.json"

      expect(response).to be_successful
      expect { join_request.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "lets the requester withdraw their own request" do
      sign_in requester
      delete "/groups/#{group.to_param}/join_requests/#{join_request.id}.json"

      expect(response).to be_successful
      expect { join_request.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
