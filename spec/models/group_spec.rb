# frozen_string_literal: true

require "rails_helper"

RSpec.describe Group do
  describe "subdomain" do
    it "accepts DNS-label subdomains" do
      %W[a den den-123 0raccoons #{"a" * 63}].each do |subdomain|
        expect(build(:group, subdomain:)).to be_valid
      end
    end

    it "rejects malformed subdomains" do
      %W[-den den- rac_coons rac.coons schöner #{"a" * 64}].each do |subdomain|
        group = build(:group, subdomain:)
        expect(group).not_to be_valid
        expect(group.errors).to be_of_kind(:subdomain, :invalid)
      end
    end

    it "rejects reserved subdomains" do
      %w[www api admin cypress].each do |subdomain|
        group = build(:group, subdomain:)
        expect(group).not_to be_valid
        expect(group.errors).to be_of_kind(:subdomain, :exclusion)
      end
    end

    it "is unique case-insensitively" do
      create :group, subdomain: "trash-pandas"
      group = build(:group, subdomain: "TRASH-Pandas")

      expect(group.subdomain).to eq("trash-pandas") # normalized
      expect(group).not_to be_valid
      expect(group.errors).to be_of_kind(:subdomain, :taken)
    end
  end

  describe "currency" do
    it "accepts any ISO 4217 code, normalizing case" do
      group = build(:group, currency: "eur")
      expect(group).to be_valid
      expect(group.currency).to eq("EUR")
    end

    it "rejects unknown codes" do
      group = build(:group, currency: "XYZ")
      expect(group).not_to be_valid
      expect(group.errors).to be_of_kind(:currency, :inclusion)
    end

    it "cannot be changed after creation" do
      group = create :group, currency: "USD"
      group.currency = "EUR"

      expect(group).not_to be_valid
      expect(group.errors).to be_of_kind(:currency, :unchangeable)
    end
  end

  describe "amount limits" do
    it "defaults to 25–2,000 minor units for two-decimal currencies" do
      group = create :group, currency: "USD"
      expect(group.min_amount_cents).to eq(25)
      expect(group.max_amount_cents).to eq(2000)
    end

    it "defaults to 25–2,000 whole units for zero-decimal currencies" do
      group = create :group, currency: "JPY"
      expect(group.min_amount_cents).to eq(25)
      expect(group.max_amount_cents).to eq(2000)
    end

    it "scales defaults for three-decimal currencies" do
      group = create :group, currency: "TND"
      expect(group.min_amount_cents).to eq(250)
      expect(group.max_amount_cents).to eq(20_000)
    end

    it "keeps explicitly provided limits" do
      group = create :group, min_amount_cents: 100, max_amount_cents: 500
      expect(group.min_amount_cents).to eq(100)
      expect(group.max_amount_cents).to eq(500)
    end

    it "rejects a maximum below the minimum" do
      group = build(:group, min_amount_cents: 500, max_amount_cents: 100)
      expect(group).not_to be_valid
      expect(group.errors).to be_of_kind(:max_amount_cents, :greater_than_or_equal_to)
    end

    it "rejects non-positive minimums" do
      group = build(:group, min_amount_cents: 0, max_amount_cents: 100)
      expect(group).not_to be_valid
      expect(group.errors).to be_of_kind(:min_amount_cents, :greater_than)
    end

    it "is backstopped by a database CHECK constraint" do
      group = create :group
      # update_columns deliberately bypasses validations to prove the DB CHECK holds on its own
      expect { group.update_columns(min_amount_cents: 500, max_amount_cents: 100) }. # rubocop:disable Rails/SkipsModelValidations
          to raise_error(ActiveRecord::StatementInvalid, /groups_amount_range_check/)
    end
  end
end
