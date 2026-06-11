# frozen_string_literal: true

class CreateOutcomes < ActiveRecord::Migration[8.1]
  def change
    create_table :outcomes do |t|
      t.references :market, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :outcomes, %i[market_id position], unique: true
    add_index :outcomes, %i[market_id name], unique: true

    # Deferred so that destroying a resolved market (and its outcomes) inside one
    # transaction does not trip the reference from markets.winning_outcome_id.
    add_foreign_key :markets, :outcomes, column: :winning_outcome_id, deferrable: :deferred
  end
end
