# frozen_string_literal: true

require "alba"

Alba.backend = :oj_rails

# ActionView template handler that treats `.alba` template source as plain Ruby
# returning a JSON String (typically `SomeSerializer.new(resource).serialize`).
module AlbaTemplateHandler
  def self.call(_template, source) = source
end

ActionView::Template.register_template_handler :alba, AlbaTemplateHandler

# ActionController::API omits view rendering. Layer ActionView::Rendering into
# ApiRendering itself (not into ApplicationController) so the API render
# pipeline stays authoritative for `render json:` — including these modules
# directly in ApplicationController inverts the ancestor chain and causes
# `format.json { render json: ... }` rescue paths to render action templates.
module ActionController
  module ApiRendering
    include ActionView::Rendering
  end
end

ActiveSupport.on_load :action_controller_api do
  include ActionController::Helpers
  include ActionController::ImplicitRender
end
