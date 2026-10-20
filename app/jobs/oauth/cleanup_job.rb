# frozen_string_literal: true

module Oauth
  # Deletes OAuth records that anyone can create without logging in once they
  # can no longer be used: authorization requests past their expiry, and
  # registered clients that no member connected within {UNUSED_CLIENT_AGE} and
  # that have no authorization in progress. Runs daily.
  class CleanupJob < ApplicationJob
    queue_as :default

    # How long a registered client may go without any member connecting it.
    UNUSED_CLIENT_AGE = 7.days

    def perform
      McpAuthorizationRequest.where(expires_at: ...Time.current).delete_all
      unused_clients.delete_all
    end

    private

    def unused_clients
      Doorkeeper::Application.where(created_at: ...UNUSED_CLIENT_AGE.ago).
          where.not(id: McpConnection.select(:application_id)).
          where.not(uid: McpAuthorizationRequest.select("parameters->>'client_id'"))
    end
  end
end
