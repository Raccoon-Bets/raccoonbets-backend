# frozen_string_literal: true

# Shared feature gating and uncached responses for browser OAuth endpoints.
# Every error renders a JSON body of the form `{"error": "<code>"}`.

class Oauth::BaseController < ApplicationController
  before_action :require_mcp_enabled!
  before_action :prevent_caching

  private

  def require_mcp_enabled!
    render json: {error: "mcp_disabled"}, status: :not_found unless Mcp::Configuration.enabled?
  end

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end

  def invalid_request(error="invalid_request")
    render json: {error:}, status: :bad_request
  end
end
