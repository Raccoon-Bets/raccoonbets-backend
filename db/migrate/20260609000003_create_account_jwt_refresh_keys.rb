# frozen_string_literal: true

class CreateAccountJwtRefreshKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :account_jwt_refresh_keys do |t|
      t.references :user, null: false, foreign_key: {on_delete: :cascade}
      t.string :key, null: false
      t.datetime :deadline, null: false
      t.index :key, unique: true
    end
  end
end
