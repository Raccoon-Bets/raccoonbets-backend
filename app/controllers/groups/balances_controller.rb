# frozen_string_literal: true

# Read-only controller for a {Group}'s ledger balances. Members only.

class Groups::BalancesController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_membership!

  # Lists every active member's realized balance in minor units of the
  # group's currency, zero balances included, largest creditors first.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/balances.json`

  def index
    balances = Groups::BalanceSheet.new(current_group).balances
    names    = current_group.memberships.where(id: balances.keys).joins(:user).pluck(:id, "users.name").to_h

    @currency = current_group.currency
    @balances = balances.
        sort_by { |membership_id, cents| [-cents, membership_id] }.
        map { |membership_id, cents| {membership_id:, name: names[membership_id], balance_cents: cents} }
  end
end
