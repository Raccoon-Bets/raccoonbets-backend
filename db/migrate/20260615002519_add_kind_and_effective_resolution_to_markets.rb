# frozen_string_literal: true

class AddKindAndEffectiveResolutionToMarkets < ActiveRecord::Migration[8.1]
  def up
    change_table :markets, bulk: true do |t|
      t.string :kind, null: false, default: "scheduled"
      t.datetime :resolution_effective_at
      t.change_null :locks_at, true
    end
    add_check_constraint :markets,
                         "(kind = 'scheduled') = (locks_at IS NOT NULL)",
                         name: "markets_locks_at_matches_kind_check"
  end

  def down
    remove_check_constraint :markets, name: "markets_locks_at_matches_kind_check"
    change_table :markets, bulk: true do |t|
      t.change_null :locks_at, false
      t.remove :resolution_effective_at, :kind
    end
  end
end
