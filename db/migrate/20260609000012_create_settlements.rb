# frozen_string_literal: true

class CreateSettlements < ActiveRecord::Migration[8.1]
  def change
    create_table :settlements do |t|
      t.references :group, null: false, foreign_key: true, index: false
      t.references :payer_membership, null: false, foreign_key: {to_table: :memberships}, index: false
      t.references :payee_membership, null: false, foreign_key: {to_table: :memberships}, index: false
      t.bigint :amount_cents, null: false
      t.string :payment_method, null: false
      t.string :note
      t.references :recorded_by, null: false, foreign_key: {to_table: :memberships}, index: false
      t.datetime :voided_at

      t.timestamps
    end

    add_index :settlements, %i[group_id created_at]
    add_check_constraint :settlements, "amount_cents > 0", name: "settlements_amount_positive_check"
  end
end
