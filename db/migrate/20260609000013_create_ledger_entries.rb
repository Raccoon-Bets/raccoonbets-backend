# frozen_string_literal: true

class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_entries do |t|
      # group_id is denormalized from the market or settlement so that
      # whole-group balance queries need no joins.
      t.references :group, null: false, foreign_key: true, index: false
      t.references :membership, null: false, foreign_key: true, index: false
      t.bigint :amount_cents, null: false
      t.string :entry_type, null: false
      t.references :market, foreign_key: true, index: false
      t.references :position, foreign_key: true, index: false
      t.references :settlement, foreign_key: true, index: false
      t.references :reverses_entry, foreign_key: {to_table: :ledger_entries}, index: false
      t.datetime :created_at, null: false
    end

    add_index :ledger_entries, %i[group_id membership_id]
    add_index :ledger_entries, :market_id
    add_index :ledger_entries, :settlement_id
    add_index :ledger_entries, :reverses_entry_id, unique: true
    add_check_constraint :ledger_entries, "amount_cents <> 0", name: "ledger_entries_amount_nonzero_check"
  end
end
