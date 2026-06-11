# frozen_string_literal: true

class CreateAccountVerificationKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :account_verification_keys, id: false do |t|
      t.bigint :id, primary_key: true # rubocop:disable Rails/DangerousColumnNames -- Rodauth convention: id is FK to users
      t.string :key, null: false
      t.datetime :requested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_foreign_key :account_verification_keys, :users, column: :id, on_delete: :cascade
  end
end
