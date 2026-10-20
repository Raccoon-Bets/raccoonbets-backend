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
    @balances = Groups::MemberQueries.new(current_membership).balances
    @currency = current_group.currency
  end
end
