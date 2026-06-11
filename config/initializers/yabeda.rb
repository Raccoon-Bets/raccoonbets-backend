# frozen_string_literal: true

# Skip metrics in test/cypress environments
return if Rails.env.test? || Rails.env.cypress?

require "yabeda/prometheus"

Yabeda.configure do
  group :raccoonbets do
    gauge :users_total,
          comment: "Total number of registered users",
          tags:    []
  end

  collect do
    raccoonbets.users_total.set({}, User.count)
  end
end

Yabeda.configure!
