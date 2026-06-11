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
    suggestions = Groups::TransferSuggester.new(Groups::BalanceSheet.new(current_group).balances).transfers
    payees      = current_group.memberships.
        where(id: suggestions.map(&:payee_membership_id)).
        includes(:user).index_by(&:id)

    @currency  = current_group.currency
    @note      = I18n.t("groups.settle_up.note", group: current_group.name)
    @transfers = suggestions.map { |transfer| transfer.to_h.merge(payee: payee_json(payees[transfer.payee_membership_id])) }
  end

  private

  def payee_json(membership)
    user = membership.user
    {
        membership_id:   membership.id,
        name:            user.name,
        venmo_handle:    user.venmo_handle,
        paypal_handle:   user.paypal_handle,
        cashapp_cashtag: user.cashapp_cashtag
    }
  end
end
