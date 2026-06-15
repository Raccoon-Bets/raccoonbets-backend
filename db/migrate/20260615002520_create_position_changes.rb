# frozen_string_literal: true

class CreatePositionChanges < ActiveRecord::Migration[8.1]
  def up
    create_table :position_changes do |t|
      t.references :market, null: false, foreign_key: true, index: false
      t.references :membership, null: false, foreign_key: true, index: false
      # Null outcome_id and amount_cents record a cancellation: the membership
      # holds no position from this point on.
      t.references :outcome, foreign_key: true, index: false
      t.bigint :amount_cents
      t.datetime :created_at, null: false
    end

    add_index :position_changes, %i[market_id membership_id created_at]
    add_index :position_changes, %i[market_id created_at]

    # Seed history for positions taken before change tracking existed, stamped
    # at the moment each member first took the side, so existing markets can be
    # resolved with an effective-as-of cutoff.
    execute <<~SQL.squish
      INSERT INTO position_changes
        (market_id, membership_id, outcome_id, amount_cents, created_at)
      SELECT market_id, membership_id, outcome_id, amount_cents, created_at
      FROM positions
    SQL
  end

  def down
    drop_table :position_changes
  end
end
