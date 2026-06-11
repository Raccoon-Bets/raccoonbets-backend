# frozen_string_literal: true

require "application_responder"

# @abstract
#
# Abstract superclass for all Raccoon Bets controllers.
#
# Standard Responses
# ------------------
#
# * When a record is not found, the response will be a 404 with the JSON body of
#   the form `{"error": "A description of the error"}`
# * When an internal error occurs, the response will be a 500 with the JSON body
#   of the form `{"error": "An internal error occurred"}` (in production) or
#   detailed error information (in development).

class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include RodauthAuthentication

  self.responder = ApplicationResponder
  respond_to :json

  around_action :switch_locale

  rescue_from StandardError, with: :other_error
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  # Renders each request's localized strings (validation errors, flash) in the
  # locale negotiated from the `Accept-Language` header, falling back to the
  # default locale. Emails use the recipient user's stored locale instead.
  def switch_locale(&)
    I18n.with_locale(locale_from_request, &)
  end

  def locale_from_request
    # The frontend sends the user's chosen locale in `X-Locale` (fetch cannot set
    # `Accept-Language`); honor it first, then fall back to the browser's header.
    explicit = matching_locale(request.headers["X-Locale"].to_s)
    return explicit if explicit

    requested = request.env["HTTP_ACCEPT_LANGUAGE"].to_s.split(",").map { |part| part.split(";").first.to_s.strip }
    requested.lazy.filter_map { |tag| matching_locale(tag) }.first || I18n.default_locale
  end

  # Resolves a BCP-47 tag to an available locale: exact match first, then a
  # locale sharing the base language (e.g. `en-GB` → `en`).
  def matching_locale(tag)
    normalized = tag.downcase
    available  = I18n.available_locales.map(&:to_s)
    available.find { |locale| locale.downcase == normalized } ||
      available.find { |locale| locale.downcase.split("-").first == normalized.split("-").first }
  end

  def not_found(error)
    respond_to do |format|
      format.json { render json: {error: error.to_s}, status: :not_found }
      format.any { head :not_found }
    end
  end

  def other_error(error)
    raise error if Rails.env.test?

    respond_to do |format|
      format.json { render json: error_json(error), status: :internal_server_error }
      format.any { head :internal_server_error }
    end
  end

  def error_json(error)
    if Rails.env.development?
      {error: error.class.to_s, message: error.to_s, backtrace: error.backtrace}
    else
      {error: I18n.t("application_controller.errors.internal_server_error")}
    end
  end
end
