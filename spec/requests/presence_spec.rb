# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /presence" do
  it "returns 200 without auth" do
    get "/presence"
    expect(response).to have_http_status(:ok)
  end

  it "is not throttled by rack-attack" do
    20.times { get "/presence", headers: {"REMOTE_ADDR" => "9.9.9.9"} }
    expect(response).to have_http_status(:ok)
  end
end
