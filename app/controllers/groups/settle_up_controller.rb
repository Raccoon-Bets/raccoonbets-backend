# frozen_string_literal: true

# Read-only controller for a {Group}'s settle-up suggestions. Members only.

class Groups::SettleUpController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_membership!

  # Suggests the transfers that zero every member's balance (greedy largest
  # debtor ↔ largest creditor, at most n−1 transfers), with each payee's
  # payment handles for building deep links, plus a note string to attach to
  # the payments.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/settle_up.json`

  def show
    result = Groups::MemberQueries.new(current_membership).settle_up
    @currency, @note, @transfers = result.values_at(:currency, :note, :transfers)
  end
end
