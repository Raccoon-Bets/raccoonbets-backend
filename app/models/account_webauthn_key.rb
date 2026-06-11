# frozen_string_literal: true

# A registered WebAuthn/passkey credential for a {User}. Used for passkey
# management (listing, renaming, deleting).
#
# Associations
# ------------
#
# |        |                                              |
# |:-------|:---------------------------------------------|
# | `user` | The {User} who owns this passkey credential. |
#
# Properties
# ----------
#
# |               |                                               |
# |:--------------|:----------------------------------------------|
# | `webauthn_id` | The credential ID (used as external key).     |
# | `label`       | User-friendly name (e.g. "My iPhone").        |
# | `last_use`    | When this credential was last used to log in. |

class AccountWebauthnKey < ApplicationRecord
  self.primary_key = %i[account_id webauthn_id]

  belongs_to :user, foreign_key: :account_id, inverse_of: :webauthn_keys
end
