# frozen_string_literal: true

# @abstract
#
# The abstract superclass for all Raccoon Bets models.

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
