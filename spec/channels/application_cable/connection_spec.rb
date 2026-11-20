# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection do
  let(:user) { create :user }

  it "connects with a valid JWT" do
    connect "/cable?jwt=#{jwt_for(user)}"
    expect(connection.current_user).to eq(user)
  end

  it "rejects a connection without a JWT" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a connection with a garbage JWT" do
    expect { connect "/cable?jwt=garbage" }.to have_rejected_connection
  end

  it "rejects a JWT that names a user but no logged-in account" do
    token = JWT.encode({"e" => user.email, "exp" => 1.hour.from_now.to_i}, Rails.application.credentials.jwt_secret, "HS256")
    expect { connect "/cable?jwt=#{token}" }.to have_rejected_connection
  end

  it "rejects a JWT for an unknown user" do
    user.destroy!
    expect { connect "/cable?jwt=#{jwt_for(user)}" }.to have_rejected_connection
  end
end
