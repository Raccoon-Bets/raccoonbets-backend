# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :market, null: false, foreign_key: true, index: false
      t.references :author_membership, null: false,
                   foreign_key: {to_table: :memberships}, index: true
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, %i[market_id created_at]
  end
end
