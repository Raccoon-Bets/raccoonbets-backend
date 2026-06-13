# frozen_string_literal: true

# A Comment is a member's free-text remark on a {Market}. Comments form a flat,
# chronological discussion: any active member of the market's group can post one
# at any time (while the market is open, resolved, or voided), the author can
# delete their own, and a group admin can delete anyone's. Comments are never
# edited.
#
# Associations
# ------------
#
# |          |                                          |
# |:---------|:------------------------------------------|
# | `market` | The {Market} being discussed.            |
# | `author` | The {Membership} that wrote the comment. |
#
# Properties
# ----------
#
# |        |                       |
# |:-------|:-----------------------|
# | `body` | The comment's text.   |

class Comment < ApplicationRecord
  belongs_to :market, inverse_of: :comments
  belongs_to :author, class_name: "Membership", foreign_key: :author_membership_id,
                      inverse_of: :comments

  # Realtime: a committed create or destroy refreshes the market's discussion
  # for every subscriber. Skipped when the comment is vanishing as part of a
  # market/group cascade delete.
  after_commit :broadcast_change, unless: :destroyed_by_association

  validates :body, presence: true, length: {maximum: 1000}
  validate :author_actively_in_group

  private

  def broadcast_change
    MarketChannel.broadcast_event market, :comment_changed
  end

  def author_actively_in_group
    return unless author && market
    return if author.group_id == market.group_id && author.active?

    errors.add(:author, :not_a_member)
  end
end
