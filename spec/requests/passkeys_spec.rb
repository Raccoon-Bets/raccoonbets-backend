# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkeys", type: :request do
  def register_key(user, webauthn_id:, label: "Phone")
    user.webauthn_keys.create!(webauthn_id:, label:, public_key: "pk-#{webauthn_id}")
  end

  it "renames and deletes the current user's own passkey" do
    user = create(:user)
    register_key(user, webauthn_id: "cred-1", label: "Old name")
    sign_in user

    patch "/account/passkeys/cred-1", params: {label: "New name"}
    expect(response).to have_http_status(:ok)
    expect(user.webauthn_keys.sole.label).to eq("New name")

    delete "/account/passkeys/cred-1"
    expect(response).to have_http_status(:no_content)
    expect(user.webauthn_keys.reload).to be_empty
  end

  it "does not let one user rename or delete another user's passkey" do
    owner = create(:user)
    register_key(owner, webauthn_id: "owner-cred", label: "Owner key")
    sign_in create(:user)

    patch "/account/passkeys/owner-cred", params: {label: "hijacked"}
    expect(response).to have_http_status(:not_found)

    delete "/account/passkeys/owner-cred"
    expect(response).to have_http_status(:not_found)

    expect(owner.webauthn_keys.sole.label).to eq("Owner key")
  end
end
