# frozen_string_literal: true

class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :currency, null: false, default: "USD", limit: 3
      t.integer :min_amount_cents, null: false
      t.integer :max_amount_cents, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :groups, "lower(subdomain)", unique: true
    add_check_constraint :groups,
                         "max_amount_cents >= min_amount_cents AND min_amount_cents > 0",
                         name: "groups_amount_range_check"
  end
end
