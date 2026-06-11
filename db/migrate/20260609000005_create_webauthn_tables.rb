# frozen_string_literal: true

class CreateWebauthnTables < ActiveRecord::Migration[8.1]
  def change
    create_table :account_webauthn_user_ids, id: false do |t|
      t.bigint :id, primary_key: true # rubocop:disable Rails/DangerousColumnNames -- Rodauth convention: id is FK to users
      t.string :webauthn_id, null: false
    end

    add_foreign_key :account_webauthn_user_ids, :users, column: :id, on_delete: :cascade

    create_table :account_webauthn_keys, primary_key: %i[account_id webauthn_id] do |t|
      t.bigint :account_id, null: false
      t.string :webauthn_id, null: false
      t.string :public_key, null: false
      t.integer :sign_count, null: false, default: 0
      t.datetime :last_use, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.string :label
    end

    add_foreign_key :account_webauthn_keys, :users, column: :account_id, on_delete: :cascade
  end
end
