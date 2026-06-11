# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack throttling" do
  before(:each) do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.cache.store.clear
  end

  it "throttles POST /signup after 3 requests per hour from the same IP" do
    4.times do |i|
      post "/signup",
           params:  {login: "rate#{i}@example.com", password: "securepass", name: "Rate #{i}"},
           headers: {"REMOTE_ADDR" => "1.2.3.4"},
           as:      :json
    end

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
    expect(response.parsed_body).to eq("error" => "Too many requests")
  end
end
