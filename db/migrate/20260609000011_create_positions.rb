# frozen_string_literal: true

class CreatePositions < ActiveRecord::Migration[8.1]
  def change
    create_table :positions do |t|
      t.references :market, null: false, foreign_key: true, index: false
      t.references :outcome, null: false, foreign_key: true
      t.references :membership, null: false, foreign_key: true
      t.integer :amount_cents, null: false

      t.timestamps
    end

    add_index :positions, %i[market_id membership_id], unique: true
    add_check_constraint :positions, "amount_cents > 0", name: "positions_amount_positive_check"
  end
end
