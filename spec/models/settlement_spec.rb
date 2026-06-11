# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settlement do
  describe "parties" do
    it "requires each party to be an active member of the settlement's group" do
      group = create(:group)

      foreign = build(:settlement, group:, payee: create(:membership))
      expect(foreign).not_to be_valid
      expect(foreign.errors[:payee]).to include("must be an active member of this group")

      requested = build(:settlement, group:, payee: create(:membership, :requested, group:))
      expect(requested).not_to be_valid
      expect(requested.errors[:payee]).to include("must be an active member of this group")
    end
  end
end
