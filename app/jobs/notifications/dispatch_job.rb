# frozen_string_literal: true

module Notifications
  # Fans a domain event out to its recipients across enabled channels. Enqueued
  # off the request path; recipient computation happens here, not in controllers.
  class DispatchJob < ApplicationJob
    queue_as :default

    # @param event [String] one of NotificationPreferences::EVENTS.
    # @param record_id [Integer] the subject record's id.
    # @param kind [String, nil] event sub-kind (e.g. "resolved"/"voided"/"corrected"/"recorded").
    def perform(event:, record_id:, kind: nil)
      record = load_record(event, record_id)
      return if record.nil?

      recipients(event, record).each do |user|
        prefs = user.notification_preferences_object
        deliver_email(event, record, kind, user) if prefs.notifies?(event, :email)
        deliver_push(event, record, kind, user) if prefs.notifies?(event, :push)
      end
    end

    private

    def load_record(event, record_id)
      klass = case event
                when "settlement"       then Settlement
                when "market_commented" then Comment
                else Market
              end
      klass.find_by(id: record_id)
    end

    def recipients(event, record)
      case event
        when "market_resolved", "market_closing_soon", "market_created"
          market_recipients(event, record)
        when "market_commented"
          comment_recipients(record)
        when "settlement"
          [record.payer.user, record.payee.user].uniq
        else
          []
      end
    end

    # The market's creator plus everyone who has commented on it, excluding the
    # member who just commented, scoped to active members (someone who has left
    # the group is not notified).
    def comment_recipients(comment)
      market         = comment.market
      author_user_id = comment.author.user_id
      commenter_ids  = market.comments.joins(:author).pluck("memberships.user_id")
      candidate_ids  = (commenter_ids + [market.creator.user_id]).uniq - [author_user_id]
      active_member_users(market.group).where(id: candidate_ids)
    end

    def market_recipients(event, market)
      case event
        when "market_resolved"
          market.positions.includes(membership: :user).map { |position| position.membership.user }.uniq
        when "market_created"
          active_member_users(market.group).where.not(id: market.creator.user_id)
        when "market_closing_soon"
          holder_ids = market.positions.joins(:membership).pluck("memberships.user_id")
          active_member_users(market.group).where.not(id: market.creator.user_id).where.not(id: holder_ids)
      end
    end

    def active_member_users(group)
      User.where(id: group.memberships.active.select(:user_id))
    end

    def deliver_email(event, record, kind, user)
      case event
        when "market_resolved"     then NotificationMailer.market_resolved(user:, market: record, kind:).deliver_later
        when "market_created"      then NotificationMailer.market_created(user:, market: record).deliver_later
        when "market_closing_soon" then NotificationMailer.market_closing_soon(user:, market: record).deliver_later
        when "market_commented"    then NotificationMailer.market_commented(user:, comment: record).deliver_later
        when "settlement"          then NotificationMailer.settlement(user:, settlement: record, kind:).deliver_later
      end
    end

    def deliver_push(event, record, kind, user)
      payload = push_payload(event, record, kind)
      user.push_subscriptions.ids.each { |id| WebPush::DeliverJob.perform_later(id, payload) }
    end

    def push_payload(event, record, _kind)
      case event
        when "market_resolved"
          {title: "Market resolved", body: record.title, url: Links.group_url(record.group, "/markets/#{record.id}")}
        when "market_created"
          {title: "New market", body: record.title, url: Links.group_url(record.group, "/markets/#{record.id}")}
        when "market_closing_soon"
          {title: "Closing soon", body: record.title, url: Links.group_url(record.group, "/markets/#{record.id}")}
        when "market_commented"
          {title: "New comment", body: record.market.title,
           url: Links.group_url(record.market.group, "/markets/#{record.market.id}")}
        when "settlement"
          {title: "Settle-up update", body: record.group.name, url: Links.group_url(record.group, "/settle-up")}
      end
    end
  end
end
