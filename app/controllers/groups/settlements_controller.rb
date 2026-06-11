# frozen_string_literal: true

# RESTful controller for a {Group}'s {Settlement}s: recording out-of-band
# payments and voiding mistaken ones. Members only. A member can record or
# void a settlement they are party to (payer or payee); admins can record or
# void any. Settlements are never deleted — `DELETE` voids, appending
# reversal ledger entries and stamping `voided_at`.

class Groups::SettlementsController < ApplicationController
  include GroupScoping

  before_action :authenticate_user!
  before_action :require_membership!
  before_action :find_settlement, only: :destroy
  before_action :load_currency

  # Lists the group's most recent settlements, voided ones included.
  #
  # Routes
  # ------
  #
  # * `GET /groups/:group_id/settlements.json`

  def index
    @settlements = current_group.settlements.
        includes(payer: :user, payee: :user, recorded_by: :user).
        order(created_at: :desc, id: :desc).
        limit(100)
    respond_with @settlements
  end

  # Records a settlement and its two ledger entries in one transaction. The
  # payer defaults to the current member; `recorded_by` is always the current
  # member.
  #
  # Routes
  # ------
  #
  # * `POST /groups/:group_id/settlements.json`
  #
  # Body Parameters
  # ---------------
  #
  # |               |                                                                                                              |
  # |:--------------|:-------------------------------------------------------------------------------------------------------------|
  # | `:settlement` | Parameterized Settlement attributes (`payer_membership_id` (optional), `payee_membership_id`, `amount_cents`, `payment_method`, `note`). |

  def create
    @settlement = current_group.settlements.new(settlement_params)
    @settlement.payer_membership_id ||= current_membership.id
    @settlement.recorded_by = current_membership
    return render_not_a_party unless party_or_admin?

    @settlement.save
    if @settlement.persisted?
      GroupChannel.broadcast_event current_group, :settlement_recorded
      Notifications::DispatchJob.perform_later(event: "settlement", record_id: @settlement.id, kind: "recorded")
    end
    respond_with @settlement
  end

  # Voids a settlement: appends reversal ledger entries and stamps
  # `voided_at`. The settlement row is never deleted.
  #
  # Routes
  # ------
  #
  # * `DELETE /groups/:group_id/settlements/:id.json`

  def destroy
    return render_not_a_party unless party_or_admin?
    return render_already_voided if @settlement.voided?

    @settlement.void!
    GroupChannel.broadcast_event current_group, :settlement_voided
    Notifications::DispatchJob.perform_later(event: "settlement", record_id: @settlement.id, kind: "voided")
    render :destroy
  end

  private

  def find_settlement
    @settlement = current_group.settlements.find(params.expect(:id))
  end

  def load_currency
    @currency = current_group.currency
  end

  def settlement_params
    params.expect(settlement: %i[payer_membership_id payee_membership_id amount_cents payment_method note])
  end

  def party_or_admin?
    current_membership.admin? ||
      [@settlement.payer_membership_id, @settlement.payee_membership_id].include?(current_membership.id)
  end

  def render_not_a_party
    render json:   {error: I18n.t("groups.settlements.errors.not_a_party")},
           status: :forbidden
  end

  def render_already_voided
    render json:   {error: I18n.t("groups.settlements.errors.already_voided")},
           status: :unprocessable_content
  end
end
