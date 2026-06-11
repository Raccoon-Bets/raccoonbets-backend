# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationPreferences do
  describe "#notifies?" do
    it "defaults every event and channel to true when unset" do
      prefs = described_class.new({})
      expect(prefs.notifies?(:market_resolved, :email)).to be(true)
      expect(prefs.notifies?(:market_created, :push)).to be(true)
    end

    it "honors an explicit false" do
      prefs = described_class.new("market_created" => {"email" => false})
      expect(prefs.notifies?(:market_created, :email)).to be(false)
      expect(prefs.notifies?(:market_created, :push)).to be(true)
    end
  end

  describe "#as_json" do
    it "fills every event x channel with the effective boolean" do
      json = described_class.new("settlement" => {"push" => false}).as_json
      expect(json["settlement"]).to eq("email" => true, "push" => false)
      expect(json.keys).to match_array(described_class::EVENTS)
    end
  end

  describe ".sanitize" do
    it "keeps only known events/channels and coerces booleans" do
      result = described_class.sanitize(
        "market_resolved" => {"email" => "false", "push" => true},
        "bogus"           => {"email" => true}
      )
      expect(result).to eq("market_resolved" => {"email" => false, "push" => true})
    end
  end
end
