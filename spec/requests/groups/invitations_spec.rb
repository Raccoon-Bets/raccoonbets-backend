# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/groups/:group_id/invitations" do
  let(:group) { create :group }
  let(:admin) { create(:membership, :admin, group:).user }
  let(:member) { create(:membership, group:).user }

  describe "GET /" do
    it "requires a group admin" do
      sign_in member
      get "/groups/#{group.to_param}/invitations.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "lists only pending invitations" do
      pending_invitation = create(:invitation, group:)
      create(:invitation, :expired, group:)
      create(:invitation, :accepted, group:)
      sign_in admin

      get "/groups/#{group.to_param}/invitations.json"

      expect(response).to be_successful
      expect(response.body).to match_json([{
                                              id:         pending_invitation.id,
                                              email:      pending_invitation.email,
                                              role:       "member",
                                              expires_at: String,
                                              created_at: String
                                          }])
    end
  end

  describe "POST /" do
    it "requires a group admin" do
      sign_in member
      post "/groups/#{group.to_param}/invitations.json",
           params: {invitation: {email: "friend@example.com"}}
      expect(response).to have_http_status(:forbidden)
    end

    context "[as admin]" do
      before(:each) { sign_in admin }

      it "creates the invitation and emails an accept link" do
        expect do
          post "/groups/#{group.to_param}/invitations.json",
               params: {invitation: {email: "friend@example.com", role: "admin"}}
        end.to have_enqueued_mail(InvitationMailer, :invite)

        expect(response).to be_successful
        invitation = group.invitations.sole
        expect(invitation.email).to eq("friend@example.com")
        expect(invitation).to be_admin
        expect(invitation.inviter).to eql(admin)

        mail = InvitationMailer.invite(invitation)
        expect(mail.to).to eq(["friend@example.com"])
        link = "#{Rails.application.config.urls.frontend}/invitations/#{invitation.token}"
        expect(mail.parts.map { |part| part.body.decoded }).to all(include(link))
      end

      it "rejects a duplicate open invitation for the same email" do
        create :invitation, group:, email: "friend@example.com"

        post "/groups/#{group.to_param}/invitations.json",
             params: {invitation: {email: "Friend@example.com"}}

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to match_json(errors: {email: [String]})
      end
    end
  end

  describe "DELETE /:id" do
    let(:invitation) { create :invitation, group: }

    it "requires a group admin" do
      sign_in member
      delete "/groups/#{group.to_param}/invitations/#{invitation.id}.json"
      expect(response).to have_http_status(:forbidden)
    end

    it "revokes a pending invitation" do
      sign_in admin
      delete "/groups/#{group.to_param}/invitations/#{invitation.id}.json"

      expect(response).to be_successful
      expect { invitation.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
