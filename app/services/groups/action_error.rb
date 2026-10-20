# frozen_string_literal: true

# Raised by {Groups::Participation} when a business rule, rather than a model
# validation, denies a member's action. The website API renders it with
# {#status}; the assistant tools return its message as a tool error.

class Groups::ActionError < StandardError
  # @return [Symbol] The HTTP status the website API responds with.
  attr_reader :status

  # @param key [String] The translation key of the error message.
  # @param status [Symbol] The HTTP status the website API responds with.

  def initialize(key, status: :forbidden)
    @status = status
    super(I18n.t(key))
  end
end
