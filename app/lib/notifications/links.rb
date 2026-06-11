# frozen_string_literal: true

module Notifications
  # Builds absolute frontend URLs on a group's subdomain (the SPA serves group
  # apps at `{subdomain}.{apex}`). Market links use the bare numeric id; the SPA
  # canonicalizes it to the slug form.
  module Links
    extend self

    def group_url(group, path)
      uri  = URI.parse(Rails.application.config.urls.frontend)
      host = uri.host
      host = "#{host}:#{uri.port}" if uri.port && [80, 443].exclude?(uri.port)
      "#{uri.scheme}://#{group.subdomain}.#{host}#{path}"
    end
  end
end
