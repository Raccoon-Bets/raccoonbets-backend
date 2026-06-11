# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupChannel do
  let(:group) { create :group }
  let(:user) { create :user }

  before(:each) { stub_connection current_user: user }

  context "[active member]" do
    before(:each) { create :membership, group:, user: }

    it "confirms the subscription and streams for the group" do
      subscribe group: group.subdomain
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(group)
    end
  end

  context "[pending join request]" do
    before(:each) { create :membership, :requested, group:, user: }

    it "rejects the subscription" do
      subscribe group: group.subdomain
      expect(subscription).to be_rejected
    end
  end

  context "[non-member]" do
    it "rejects the subscription" do
      subscribe group: group.subdomain
      expect(subscription).to be_rejected
    end
  end

  context "[suspended group]" do
    let(:group) { create :group, :suspended }

    before(:each) { create :membership, group:, user: }

    it "rejects the subscription" do
      subscribe group: group.subdomain
      expect(subscription).to be_rejected
    end
  end

  context "[unknown slug]" do
    it "rejects the subscription" do
      subscribe group: "nonexistent"
      expect(subscription).to be_rejected
    end
  end
end
