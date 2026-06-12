# frozen_string_literal: true

# Action Cable channel for a {Group}'s activity. Subscribers are notified
# whenever something group-wide changes, and refetch what they display.
#
# Parameters
# ----------
#
# |         |                                |
# |:--------|:-------------------------------|
# | `group` | The group's subdomain slug.    |
#
# Only active members of an active group may subscribe.
#
# Events
# ------
#
# Every payload is `{type:, ...}`. Market events carry the market's ID so
# subscribers can refetch or ignore selectively:
#
# * `market_created`, `market_updated` — `{type:, market_id:}` (`market_updated`
#   also fires when a position changes the market's pools)
# * `market_deleted` — `{type:, market_id:}`
# * `market_resolved`, `market_voided`, `market_corrected` — `{type:, market_id:}`
# * `settlement_recorded`, `settlement_voided` — `{type:}`
# * `member_joined` — `{type:}`

class GroupChannel < ApplicationCable::Channel

  # @private
  def subscribed
    group = Group.active.find_by(subdomain: params[:group])
    return reject unless group&.memberships&.exists?(user: current_user, status: :active)

    stream_for group
  end

  # Broadcasts an event to the group's subscribers.
  #
  # @param group [Group] The group whose subscribers to notify.
  # @param type [Symbol, String] The event type (see class docs).
  # @param extra [Hash] Additional payload fields (e.g. `market_id`).

  def self.broadcast_event(group, type, **extra)
    broadcast_to group, {type:, **extra}
  end
end
