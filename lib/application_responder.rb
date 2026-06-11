# frozen_string_literal: true

# The default responder for all controller actions; defines the universal
# behavior of the API.

class ApplicationResponder < ActionController::Responder
  include Responders::FlashResponder
  include Responders::HttpCacheResponder

  # @private
  def api_behavior
    raise MissingRenderer, format unless has_renderer?

    if put? || patch?
      display resource, location: api_location
    else
      super
    end
  end

  # @private
  def display(resource, given_options={})
    if resource.kind_of?(Enumerable)
      controller.render "index", given_options
    else
      controller.render "show", given_options
    end
  end
end
