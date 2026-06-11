# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :request) do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.store.clear
  end
end
