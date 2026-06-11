# frozen_string_literal: true

# Container module for Action Cable classes.

module ApplicationCable

  # The base Action Cable connection class. Handles authenticating WebSocket
  # connections.
  #
  # Connections are identified by a {User}'s JSON web token (JWT). When
  # making a request to `/cable`, pass the JWT as a query parameter
  # (`/cable?jwt=abc123`). The user is looked up by the JWT's `e` (email)
  # claim, which {RodauthApp} adds to every access token.

  class Connection < ActionCable::Connection::Base

    # @return [Hash] The decoded JWT payload.
    attr_reader :jwt

    identified_by :current_user

    # @private
    def connect
      token = request.params[:jwt]
      reject_unauthorized_connection unless token

      @jwt = decode_jwt(token)
      self.current_user = find_verified_user
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
      reject_unauthorized_connection
    end

    private

    def find_verified_user = User.find_by!(email: jwt["e"])

    def decode_jwt(token)
      secret = Rails.application.credentials.jwt_secret
      JWT.decode(token, secret, true, algorithm: "HS256").first
    end
  end
end
