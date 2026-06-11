# frozen_string_literal: true

# Provides authentication helpers backed by Rodauth.
# Include in ApplicationController to make `authenticate_user!`,
# `current_user`, `user_signed_in?`, and `require_superadmin!` available in
# all controllers.

module RodauthAuthentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :user_signed_in?
  end

  private

  def authenticate_user!
    return if rodauth.logged_in?

    render json:   {error: "You need to sign in or sign up before continuing."},
           status: :unauthorized
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: rodauth.session_value) if rodauth.logged_in?
  end

  def user_signed_in?
    rodauth.logged_in?
  end

  def require_superadmin!
    return if current_user&.superadmin?

    render json:   {error: I18n.t("rodauth_authentication.errors.not_a_superadmin")},
           status: :forbidden
  end
end
