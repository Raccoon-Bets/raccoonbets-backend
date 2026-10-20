# frozen_string_literal: true

# Starts authorization and carries validated parameters to the website's consent screen.
class Oauth::AuthorizationsController < Oauth::BaseController
  # Redirects to a short-lived consent request without placing login tokens in the URL.
  def create
    attributes = params.permit(:client_id, :redirect_uri, :response_type, :scope, :state,
                               :code_challenge, :code_challenge_method, :resource).to_h.symbolize_keys
    application = Doorkeeper::Application.find_by(uid: attributes[:client_id])
    return invalid_request unless valid_request?(application, attributes)

    identifier = SecureRandom.urlsafe_base64(32)
    McpAuthorizationRequest.create!(identifier:, parameters: attributes,
                                    expires_at: 10.minutes.from_now)
    redirect_to "#{Rails.application.config.urls.frontend}/oauth/consent/#{identifier}", allow_other_host: true
  end

  private

  def valid_request?(application, attributes)
    application && attributes[:resource] == Mcp::Configuration.resource &&
      application.redirect_uri.split.include?(attributes[:redirect_uri]) &&
      attributes[:code_challenge_method] == "S256" &&
      attributes[:code_challenge].to_s.match?(/\A[A-Za-z0-9_-]{43}\z/) &&
      Doorkeeper::OAuth::PreAuthorization.new(Doorkeeper.configuration, attributes).authorizable?
  end
end
