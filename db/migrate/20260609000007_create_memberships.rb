# frozen_string_literal: true

class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :group, null: false, foreign_key: true, index: false
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "active"
      t.references :invited_by, foreign_key: {to_table: :users}, index: false

      t.timestamps
    end

    add_index :memberships, %i[group_id user_id], unique: true
    add_index :memberships, %i[group_id status]
  end
end
