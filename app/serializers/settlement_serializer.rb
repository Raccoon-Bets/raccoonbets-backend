# frozen_string_literal: true

# A {Settlement} with its parties' names. Amounts are minor units of
# `currency`.
#
# Params
# ------
#
# |             |                                       |
# |:------------|:----------------------------------------|
# | `:currency` | The group's ISO 4217 currency code.   |

class SettlementSerializer < ApplicationSerializer
  attributes :id, :amount_cents, :payment_method, :note, :voided_at, :created_at

  attribute :currency do
    params[:currency]
  end

  attribute :voided, &:voided?

  attribute :payer do |settlement|
    membership_ref settlement.payer
  end

  attribute :payee do |settlement|
    membership_ref settlement.payee
  end

  attribute :recorded_by do |settlement|
    membership_ref settlement.recorded_by
  end

  private

  def membership_ref(membership)
    {id: membership.id, name: membership.user.name}
  end
end
