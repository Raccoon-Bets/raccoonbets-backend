# frozen_string_literal: true

# A linked external login (Google, Apple) for a {User}. Rows are written by
# rodauth-omniauth during the OAuth callback; this model exists for the
# ActiveRecord side of the app to read and manage them.
#
# Associations
# ------------
#
# |        |                                          |
# |:-------|:-----------------------------------------|
# | `user` | The {User} this external identity logs in. |
#
# Properties
# ----------
#
# |            |                                                        |
# |:-----------|:-------------------------------------------------------|
# | `provider` | The OmniAuth provider name (e.g. "google", "apple").   |
# | `uid`      | The provider's stable identifier for the user.         |

class AccountIdentity < ApplicationRecord
  belongs_to :user, inverse_of: :identities
end
