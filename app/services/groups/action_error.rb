# frozen_string_literal: true

# A member action denied by a business rule rather than a model validation.
class Groups::ActionError < StandardError
  attr_reader :status

  # @param key [String] translation key describing the denied action.
  # @param status [Symbol] HTTP status shared by REST and MCP error responses.
  def initialize(key, status: :forbidden)
    @status = status
    super(I18n.t(key))
  end
end
