# frozen_string_literal: true

class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :group, null: false, foreign_key: true, index: false
      t.references :inviter, null: false, foreign_key: {to_table: :users}, index: false
      t.string :email, null: false
      t.string :role, null: false, default: "member"
      t.string :token, null: false
      t.datetime :accepted_at
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, "group_id, lower(email)",
              unique: true,
              where:  "accepted_at IS NULL",
              name:   "index_invitations_on_group_and_email_open"
  end
end
