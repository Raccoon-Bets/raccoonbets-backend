# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/invitations" do
  let(:group) { create :group }
  let(:inviter) { create(:membership, :admin, group:).user }
  let(:user) { create :user }
  let(:invitation) { create :invitation, group:, inviter:, email: user.email }

  describe "GET /:token" do
    it "requires a logged-in user" do
      get "/invitations/#{invitation.token}.json"
      expect(response).to have_http_status(:unauthorized)
    end

    context "[authenticated]" do
      before(:each) { sign_in user }

      it "previews the invitation" do
        get "/invitations/#{invitation.token}.json"

        expect(response).to be_successful
        expect(response.body).to match_json(
                                   email:        invitation.email,
                                   role:         "member",
                                   expires_at:   String,
                                   group_name:   group.name,
                                   inviter_name: inviter.name,
                                   valid:        true
                                 )
      end

      it "marks expired invitations invalid" do
        invitation.update! expires_at: 1.day.ago
        get "/invitations/#{invitation.token}.json"

        expect(response).to be_successful
        expect(response.body).to match_json(hash_including(valid: false))
      end

      it "returns 404 for unknown tokens" do
        get "/invitations/unknown-token.json"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /:token/accept" do
    it "requires a logged-in user" do
      post "/invitations/#{invitation.token}/accept.json"
      expect(response).to have_http_status(:unauthorized)
    end

    context "[authenticated]" do
      before(:each) { sign_in user }

      it "creates an active membership with the invitation's role" do
        invitation.update! role: "admin"

        post "/invitations/#{invitation.token}/accept.json"

        expect(response).to be_successful
        expect(response.body).to match_json(hash_including(
                                              subdomain:  group.to_param,
                                              membership: {id: Integer, role: "admin"}
                                            ))

        membership = group.memberships.find_by!(user:)
        expect(membership).to be_active
        expect(membership).to be_admin
        expect(membership.invited_by).to eql(inviter)
        expect(invitation.reload).to be_accepted
      end

      it "activates a pending join request instead of failing" do
        join_request = create(:membership, :requested, group:, user:)

        post "/invitations/#{invitation.token}/accept.json"

        expect(response).to be_successful
        expect(join_request.reload).to be_active
        expect(invitation.reload).to be_accepted
      end

      it "succeeds idempotently when the user is already an active member" do
        create(:membership, group:, user:)

        post "/invitations/#{invitation.token}/accept.json"

        expect(response).to be_successful
        expect(group.memberships.where(user:).count).to eq(1)
      end

      it "returns 410 for expired invitations" do
        invitation.update! expires_at: 1.day.ago

        post "/invitations/#{invitation.token}/accept.json"

        expect(response).to have_http_status(:gone)
        expect(group.memberships.where(user:)).to be_empty
      end

      it "returns 410 for already-accepted invitations" do
        invitation.update! accepted_at: 1.hour.ago

        post "/invitations/#{invitation.token}/accept.json"

        expect(response).to have_http_status(:gone)
        expect(group.memberships.where(user:)).to be_empty
      end
    end
  end
end
