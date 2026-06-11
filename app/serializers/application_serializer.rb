# frozen_string_literal: true

class ApplicationSerializer
  include Alba::Resource

  def self.destroyed_aware_attributes(*names)
    attribute(:destroyed?, if: proc { |obj| obj.destroyed? }) { true }
    attributes(*names, if: proc { |obj| !obj.destroyed? })
  end
end
