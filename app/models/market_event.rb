# frozen_string_literal: true

# A MarketEvent is one entry in a {Market}'s audit trail: who resolved, voided,
# or corrected it, to which {Outcome}, and when. Events are written by
# {Markets::Resolver} alongside the state change and its ledger entries.
#
# Associations
# ------------
#
# |           |                                                          |
# |:----------|:----------------------------------------------------------|
# | `market`  | The {Market} the event happened to.                      |
# | `actor`   | The {Membership} that performed the action.              |
# | `outcome` | The {Outcome} resolved or corrected to, if applicable.   |
#
# Properties
# ----------
#
# |          |                                       |
# |:---------|:---------------------------------------|
# | `action` | `resolved`, `voided`, or `corrected`. |
# | `note`   | Optional free-text note.              |

class MarketEvent < ApplicationRecord
  belongs_to :market, inverse_of: :market_events
  belongs_to :actor, class_name: "Membership", foreign_key: :actor_membership_id,
                      inverse_of: :market_events
  belongs_to :outcome, optional: true

  enum :action, {resolved: "resolved", voided: "voided", corrected: "corrected"}, validate: true

  validates :note, length: {maximum: 500}, allow_nil: true
end
