# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Links do
  it "builds a group subdomain URL from the configured frontend host" do
    group = build_stubbed(:group, subdomain: "trash-pandas")
    allow(Rails.application.config.urls).to receive(:frontend).and_return("https://raccoonbets.org")
    expect(described_class.group_url(group, "/markets/42")).to eq("https://trash-pandas.raccoonbets.org/markets/42")
  end

  it "preserves a non-standard port (development)" do
    group = build_stubbed(:group, subdomain: "trash-pandas")
    allow(Rails.application.config.urls).to receive(:frontend).and_return("http://lvh.me:5173")
    expect(described_class.group_url(group, "/settle-up")).to eq("http://trash-pandas.lvh.me:5173/settle-up")
  end
end
