# frozen_string_literal: true

# Per-event notification emails. Each method is invoked only after the
# dispatcher confirms the recipient has the email channel enabled for the event.
class NotificationMailer < ApplicationMailer
  # @param user [User] the recipient.
  # @param market [Market] the resolved market.
  # @param kind [String] "resolved", "voided", or "corrected".
  def market_resolved(user:, market:, kind:)
    @user = user
    @market = market
    @kind = kind
    @link = Notifications::Links.group_url(market.group, "/markets/#{market.id}")
    mail_localized user, "notification_mailer.market_resolved.subject", title: market.title
  end

  # @param user [User] the recipient.
  # @param market [Market] the new market.
  def market_created(user:, market:)
    @user = user
    @market = market
    @link = Notifications::Links.group_url(market.group, "/markets/#{market.id}")
    mail_localized user, "notification_mailer.market_created.subject", group: market.group.name
  end

  # @param user [User] the recipient (payer or payee).
  # @param settlement [Settlement] the settlement.
  # @param kind [String] "recorded" or "voided".
  def settlement(user:, settlement:, kind:)
    @user = user
    @settlement = settlement
    @kind = kind
    @link = Notifications::Links.group_url(settlement.group, "/settle-up")
    mail_localized user, "notification_mailer.settlement.subject", group: settlement.group.name
  end

  # @param user [User] the recipient.
  # @param market [Market] the market nearing its lock time.
  def market_closing_soon(user:, market:)
    @user = user
    @market = market
    @link = Notifications::Links.group_url(market.group, "/markets/#{market.id}")
    mail_localized user, "notification_mailer.market_closing_soon.subject", title: market.title
  end

  # @param user [User] the recipient (market creator or a prior commenter).
  # @param comment [Comment] the new comment.
  def market_commented(user:, comment:)
    @user = user
    @comment = comment
    @market = comment.market
    @author_name = comment.author.user.name
    @link = Notifications::Links.group_url(@market.group, "/markets/#{@market.id}")
    mail_localized user, "notification_mailer.market_commented.subject", title: @market.title
  end
end
