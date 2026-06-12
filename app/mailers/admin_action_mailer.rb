# frozen_string_literal: true

# Mandatory notices for admin (and creator) actions that affect another
# member's position: market edits, market deletion, and admin position
# cancellation. These deliberately bypass {NotificationPreferences} — anyone
# whose position is touched by someone else is always told by email, with no
# opt-out. Email only; no push.

class AdminActionMailer < ApplicationMailer
  helper do
    # Renders one side of an old → new change summary: times in the
    # recipient's locale, blanks as a placeholder.
    def change_value(value)
      return l(value, format: :long) if value.respond_to?(:strftime)

      value.to_s.presence || t("admin_action_mailer.market_edited.blank")
    end
  end

  # @param user [User] the recipient (a position holder other than the actor).
  # @param market [Market] the edited market.
  # @param actor_name [String] the name of the member who edited it.
  # @param changes [Hash{String => Array}] changed fields mapped to `[old, new]`.
  def market_edited(user:, market:, actor_name:, changes:)
    @user       = user
    @market     = market
    @actor_name = actor_name
    @changes    = changes
    @link       = Notifications::Links.group_url(market.group, "/markets/#{market.id}")
    mail_localized user, "admin_action_mailer.market_edited.subject", title: market.title
  end

  # @param user [User] the recipient (a position holder other than the actor).
  # @param group [Group] the group the market belonged to.
  # @param market_title [String] the deleted market's title.
  # @param actor_name [String] the name of the admin who deleted it.
  def market_deleted(user:, group:, market_title:, actor_name:)
    @user         = user
    @group        = group
    @market_title = market_title
    @actor_name   = actor_name
    @link         = Notifications::Links.group_url(group, "/")
    mail_localized user, "admin_action_mailer.market_deleted.subject", title: market_title
  end

  # @param user [User] the position's owner.
  # @param market [Market] the market the position was on.
  # @param actor_name [String] the name of the admin who cancelled it.
  # @param amount_cents [Integer] the cancelled stake, in minor units.
  def position_cancelled(user:, market:, actor_name:, amount_cents:)
    @user       = user
    @market     = market
    @actor_name = actor_name
    @amount     = formatted_amount(amount_cents, market.group.currency)
    @link       = Notifications::Links.group_url(market.group, "/markets/#{market.id}")
    mail_localized user, "admin_action_mailer.position_cancelled.subject", title: market.title
  end

  private

  # Formats minor units as "5.50 USD". The app otherwise renders money
  # client-side, so there are no i18n currency formats to lean on; the money
  # gem supplies only the ISO 4217 exponent.
  def formatted_amount(amount_cents, currency)
    money  = Money.from_cents(amount_cents, currency)
    amount = ActiveSupport::NumberHelper.number_to_rounded(money.amount, precision: money.currency.exponent)
    "#{amount} #{currency}"
  end
end
