# frozen_string_literal: true

class AddPushPromptDismissedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :push_prompt_dismissed_at, :datetime
  end
end
