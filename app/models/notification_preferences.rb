# frozen_string_literal: true

# A plain value object over a User's `notification_preferences` jsonb. Every
# event x channel defaults to ON; only explicit `false` overrides are stored.
class NotificationPreferences
  EVENTS   = %w[market_resolved market_created settlement market_closing_soon market_commented].freeze
  CHANNELS = %w[email push].freeze

  def initialize(raw)
    @raw = raw || {}
  end

  # @return [Boolean] whether the user wants `channel` for `event` (default true).
  def notifies?(event, channel)
    @raw.dig(event.to_s, channel.to_s) != false
  end

  # @return [Hash] every event x channel with its effective boolean (defaults filled).
  def as_json(*)
    EVENTS.index_with { |event| CHANNELS.index_with { |channel| notifies?(event, channel) } }
  end

  # Whitelists to known event/channel keys and coerces to real booleans.
  # @param input [Hash] untrusted preferences from params.
  # @return [Hash] safe to persist.
  def self.sanitize(input)
    (input || {}).slice(*EVENTS).each_with_object({}) do |(event, channels), out|
      cleaned = (channels || {}).slice(*CHANNELS).transform_values do |value|
        ActiveModel::Type::Boolean.new.cast(value) == true
      end
      out[event] = cleaned unless cleaned.empty?
    end
  end
end
