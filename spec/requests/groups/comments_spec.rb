# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/markets/:market_id/comments" do
  include ActiveJob::TestHelper

  let(:group) { create :group }
  let(:membership) { create :membership, group: }
  let(:member) { membership.user }
  let(:market) { create :market, group: }
  let(:path) { "/groups/#{group.to_param}/markets/#{market.id}/comments.json" }

  describe "POST /" do
    it "rejects non-members" do
      sign_in create(:user)
      post path, params: {comment: {body: "Hi"}}
      expect(response).to have_http_status(:forbidden)
    end

    it "posts a comment and returns it in the market detail" do
      sign_in member
      post path, params: {comment: {body: "Calling it now."}}

      expect(response).to be_successful
      comment = market.comments.sole
      expect(comment.body).to eq("Calling it now.")
      expect(comment.author).to eq(membership)
      bodies = response.parsed_body["comments"].pluck("body")
      expect(bodies).to include("Calling it now.")
    end

    it "allows comments on a resolved market" do
      resolved = create(:market, :resolved, group:)
      sign_in member
      post "/groups/#{group.to_param}/markets/#{resolved.id}/comments.json", params: {comment: {body: "GG"}}

      expect(response).to be_successful
      expect(resolved.comments.sole.body).to eq("GG")
    end

    it "rejects a blank comment" do
      sign_in member
      post path, params: {comment: {body: " "}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("errors", "body")).to be_present
      expect(market.comments).to be_empty
    end

    it "enqueues a notification dispatch" do
      sign_in member
      expect do
        post path, params: {comment: {body: "Heads up"}}
      end.to have_enqueued_job(Notifications::DispatchJob).
          with(event: "market_commented", record_id: kind_of(Integer))
    end
  end

  describe "DELETE /:id" do
    let(:comment) { create :comment, market:, author: membership }
    let(:comment_path) { "/groups/#{group.to_param}/markets/#{market.id}/comments/#{comment.id}.json" }

    it "lets the author delete their own comment" do
      sign_in member
      delete comment_path

      expect(response).to be_successful
      expect(Comment.exists?(comment.id)).to be(false)
    end

    it "lets a group admin delete another member's comment" do
      admin = create(:membership, :admin, group:)
      sign_in admin.user
      delete comment_path

      expect(response).to be_successful
      expect(Comment.exists?(comment.id)).to be(false)
    end

    it "forbids a non-author, non-admin member" do
      other = create(:membership, group:)
      sign_in other.user
      delete comment_path

      expect(response).to have_http_status(:forbidden)
      expect(Comment.exists?(comment.id)).to be(true)
    end
  end
end
