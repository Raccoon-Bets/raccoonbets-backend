# frozen_string_literal: true

require "rails_helper"

RSpec.describe Outcome do
  describe "immutability" do
    let(:market) { create :market }
    let(:outcome) { market.outcomes.first }

    it "allows renaming and repositioning before any positions" do
      expect(outcome.update(name: "MAYBE", position: 5)).to be(true)
    end

    it "freezes name and position once the market has positions" do
      create(:position, market:)

      outcome.assign_attributes name: "MAYBE", position: 5
      expect(outcome).not_to be_valid
      expect(outcome.errors[:name]).to include("cannot be changed")
      expect(outcome.errors[:position]).to include("cannot be changed")
    end
  end
end
