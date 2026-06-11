# frozen_string_literal: true

# Responds to requests by resetting the Cypress test environment. The reset
# test environment consists of two verified Users — `cypress@example.com`,
# the admin of one Group ("Cypress Den" at `cypress-den`), and
# `cypress2@example.com`, an active member of the same group.
#
# The response to the request will be the admin User's email.
#
# This middleware must be mounted at a specific route, not added to the
# middleware chain.

class Cypress::Reset
  def call(_env)
    reset_cypress
    user = create_user
    create_group user
    return response(user)
  end

  private

  def reset_cypress
    models.each { truncate it }
    ActionMailer::Base.deliveries.clear
    return unless defined?(Rack::Attack)

    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.store.clear
  end

  def response(user) = [200, {"Content-Type" => "text/plain"}, [user.email]]

  def models = [User, Group]

  def truncate(model)
    model.connection.execute "TRUNCATE #{model.quoted_table_name} CASCADE"
  end

  def create_user = create_verified_user("cypress@example.com", "Cypress User")

  def create_group(user)
    group = Group.create! name: "Cypress Den", subdomain: "cypress-den"
    group.memberships.create! user:, role: :admin, status: :active
    group.memberships.create! user:   create_verified_user("cypress2@example.com", "Cypress Friend"),
                              role:   :member,
                              status: :active
    group
  end

  def create_verified_user(email, name)
    user = User.create! email:, name:, password: "supersecret"
    user.update! status_id: 2
    user
  end
end
