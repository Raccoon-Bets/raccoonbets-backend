# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false

      # Rodauth account columns
      t.string :password_hash
      t.integer :status_id, null: false, default: 1

      t.string :locale
      t.boolean :superadmin, null: false, default: false

      # Settle-up payment handles (links built by the frontend)
      t.string :venmo_handle
      t.string :paypal_handle
      t.string :cashapp_cashtag

      t.timestamps null: false
    end

    add_index :users, :email, unique: true
  end
end
