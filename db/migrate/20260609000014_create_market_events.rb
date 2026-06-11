# frozen_string_literal: true

class CreateMarketEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :market_events do |t|
      t.references :market, null: false, foreign_key: true
      t.references :actor_membership, null: false, foreign_key: {to_table: :memberships}, index: false
      t.string :action, null: false
      t.references :outcome, foreign_key: true, index: false
      t.string :note
      t.datetime :created_at, null: false
    end
  end
end
