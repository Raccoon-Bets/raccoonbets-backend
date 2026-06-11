# frozen_string_literal: true

class CreateAccountPasswordResetKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :account_password_reset_keys, id: false do |t|
      t.bigint :id, primary_key: true # rubocop:disable Rails/DangerousColumnNames -- Rodauth convention: id is FK to users
      t.string :key, null: false
      t.datetime :deadline, null: false
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_foreign_key :account_password_reset_keys, :users, column: :id, on_delete: :cascade
  end
end
