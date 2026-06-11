# frozen_string_literal: true

class AddClosingSoonNotifiedAtToMarkets < ActiveRecord::Migration[8.1]
  def change
    add_column :markets, :closing_soon_notified_at, :datetime
  end
end
