# frozen_string_literal: true

class CreateMarkets < ActiveRecord::Migration[8.1]
  def change
    create_table :markets do |t|
      t.references :group, null: false, foreign_key: true, index: false
      t.references :creator, null: false, foreign_key: {to_table: :memberships}, index: false
      t.references :oracle, null: false, foreign_key: {to_table: :memberships}, index: false
      t.string :title, null: false, limit: 200
      t.text :description
      t.datetime :locks_at, null: false
      t.string :status, null: false, default: "open"

      # The foreign key to outcomes is added in CreateOutcomes, after the
      # outcomes table exists.
      t.bigint :winning_outcome_id
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: {to_table: :memberships}, index: false

      t.timestamps
    end

    add_index :markets, %i[group_id status]
    add_index :markets, %i[group_id locks_at]
    add_check_constraint :markets,
                         "(status = 'resolved') = (winning_outcome_id IS NOT NULL)",
                         name: "markets_resolved_iff_winning_outcome_check"
  end
end
