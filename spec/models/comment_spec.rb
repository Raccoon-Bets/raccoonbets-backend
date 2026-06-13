# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comment do
  let(:market) { create :market }

  describe "body" do
    it "requires a body" do
      comment = build(:comment, market:, body: " ")
      expect(comment).not_to be_valid
      expect(comment.errors).to be_of_kind(:body, :blank)
    end

    it "caps the body length" do
      comment = build(:comment, market:, body: "x" * 1001)
      expect(comment).not_to be_valid
      expect(comment.errors).to be_of_kind(:body, :too_long)
    end
  end

  describe "author" do
    it "requires the author to be an active member of the market's group" do
      foreign = build(:comment, market:, author: create(:membership))
      expect(foreign).not_to be_valid
      expect(foreign.errors[:author]).to include("must be an active member of this group")

      requested = build(:comment, market:, author: create(:membership, :requested, group: market.group))
      expect(requested).not_to be_valid
      expect(requested.errors[:author]).to include("must be an active member of this group")
    end
  end
end
