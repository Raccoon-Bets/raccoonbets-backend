# frozen_string_literal: true

# A {Comment} with its author's name. The viewer decides deletability client-side
# from the author id and their own role (mirroring positions), so no permission
# flag is serialized.

class CommentSerializer < ApplicationSerializer
  attributes :id, :body, :created_at

  attribute :author do |comment|
    {id: comment.author_membership_id, name: comment.author.user.name}
  end
end
