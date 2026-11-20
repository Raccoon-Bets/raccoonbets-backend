# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

RSpec.describe "Passkeys" do
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

  describe "passkey ceremonies" do
    let(:password) { Faker::Internet.password }
    let(:user) { create(:user, password:) }
    let(:client) { WebAuthn::FakeClient.new(Rails.application.config.urls.frontend) }

    def bearer(jwt) = {"Authorization" => "Bearer #{jwt}"}

    def jwt_payload(jwt)
      JWT.decode(jwt, Rails.application.credentials.jwt_secret, true, algorithm: "HS256").first
    end

    # Requests a ceremony's options, returning them with the JWT that binds
    # their challenge to the requesting session.
    def ceremony_options(path, headers: {})
      post(path, headers:, as: :json)
      [response.parsed_body, response.headers["Authorization"]]
    end

    def base64url(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

    # Adds the fields a browser's PublicKeyCredential#toJSON reports alongside
    # the attestation, which carry a real registration past Rodauth's
    # parameter size cap.
    def browser_json(credential)
      auth_data = CBOR.decode(Base64.urlsafe_decode64(credential.dig("response", "attestationObject")))["authData"]
      public_key = WebAuthn::AuthenticatorData.deserialize(auth_data).credential.public_key_object
      browser_fields = {
          "authenticatorData"  => base64url(auth_data),
          "publicKey"          => base64url(public_key.public_to_der),
          "publicKeyAlgorithm" => COSE::Algorithm.by_name("ES256").id
      }
      credential.deep_merge("response" => browser_fields)
    end

    def log_in_with_password
      post "/login", params: {login: user.email, password:}, as: :json
      response.headers["Authorization"]
    end

    def register_passkey
      options, jwt = ceremony_options("/webauthn-setup", headers: bearer(log_in_with_password))
      challenge = options["webauthn_setup_challenge"]
      post "/webauthn-setup",
           headers: bearer(jwt),
           params:  {
               webauthn_setup:                browser_json(client.create(challenge:)),
               webauthn_setup_challenge:      challenge,
               webauthn_setup_challenge_hmac: options["webauthn_setup_challenge_hmac"],
               password:
           },
           as:      :json
      expect(response).to have_http_status(:success)
    end

    it "logs in with a passkey through the challenge's pre-login JWT" do
      register_passkey

      options, jwt = ceremony_options("/webauthn-login")
      expect(jwt_payload(jwt)).not_to include("account_id", "e")

      challenge = options["webauthn_auth_challenge"]
      post "/webauthn-login",
           headers: bearer(jwt),
           params:  {
               webauthn_auth:                client.get(challenge:),
               webauthn_auth_challenge:      challenge,
               webauthn_auth_challenge_hmac: options["webauthn_auth_challenge_hmac"]
           },
           as:      :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body["email"]).to eq(user.email)
      expect(jwt_payload(response.headers["Authorization"])).to include("account_id" => user.id, "e" => user.email)
    end

    it "refuses a passkey login naming a login, whether or not the account exists" do
      register_passkey

      refusals = [user.email, "nobody@example.com"].map do |login|
        post "/webauthn-login", params: {login:}, as: :json
        expect(response.headers["Authorization"]).to be_blank
        [response.status, response.parsed_body]
      end

      expect(refusals.uniq.size).to eq(1)
      expect(refusals.first.last).not_to include("webauthn_auth", "webauthn_auth_challenge_hmac")
    end
  end
end
