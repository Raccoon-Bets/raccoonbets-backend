# frozen_string_literal: true

# A Group is a private den of friends trading against each other, hosted on
# its own subdomain of raccoonbets.org. All amounts within a Group are integer
# minor units ("cents") of the Group's single currency.
#
# The `currency` cannot be changed after the Group is created: amount limits and
# (in later phases) positions and ledger entries are all denominated in it, and
# reinterpreting stored minor units in another currency would corrupt them.
#
# Associations
# ------------
#
# |               |                                                          |
# |:--------------|:---------------------------------------------------------|
# | `memberships` | The {Membership}s tying {User}s to this Group.           |
# | `users`       | The {User}s belonging to this Group (any status).        |
# | `invitations` | Outstanding and accepted email {Invitation}s.            |
# | `markets`     | The {Market}s the group's members trade on.              |
#
# Properties
# ----------
#
# |                    |                                                                                |
# |:-------------------|:-------------------------------------------------------------------------------|
# | `name`             | The display name of the group.                                                 |
# | `subdomain`        | The group's subdomain of raccoonbets.org; unique, lowercase, DNS-label format. |
# | `currency`         | The ISO 4217 code all the group's amounts are denominated in. Immutable.       |
# | `min_amount_cents` | The smallest allowed position, in minor units of `currency`.                   |
# | `max_amount_cents` | The largest allowed position, in minor units of `currency`.                    |
# | `status`           | `active`, or `suspended` by a superadmin (suspended groups 404 everywhere).    |

class Group < ApplicationRecord
  # DNS-label format: lowercase alphanumerics and hyphens, no leading/trailing
  # hyphen, at most 63 characters.
  SUBDOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

  # Subdomains reserved for infrastructure or future use; never available to
  # groups.
  RESERVED_SUBDOMAINS = %w[
      admin api app assets blog cable cdn cypress demo dev docs ftp help imap
      legal mail news pop raccoonbets smtp staging static status support test
      web www ws
  ].freeze

  # Default amount limits, in minor units, for a currency with 100 subunits per
  # unit (e.g. 25¢–$20 for USD). Currencies with other subunit ratios scale
  # these by `(subunit_to_unit / 100).ceil`, so zero-decimal currencies like
  # JPY default to ¥25–¥2,000 and three-decimal currencies like TND default to
  # 250–20,000 millimes (0.25–20 TND).
  DEFAULT_MIN_AMOUNT_CENTS = 25
  DEFAULT_MAX_AMOUNT_CENTS = 2000

  # Dependent associations are declared in deletion order. Ledger entries go
  # first (they hold foreign keys to everything else) via `delete_all`, which
  # bypasses {LedgerEntry#readonly?} — the only sanctioned way the append-only
  # ledger ever shrinks. Settlements go next (ledger entries reference them),
  # then markets (and their events, positions, and outcomes), then memberships.
  has_many :ledger_entries, dependent: :delete_all
  has_many :settlements, dependent: :delete_all
  has_many :markets, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy

  enum :status, {active: "active", suspended: "suspended"}, validate: true

  normalizes :subdomain, with: ->(subdomain) { subdomain.strip.downcase }
  normalizes :currency, with: ->(currency) { currency.strip.upcase }

  before_validation :apply_default_amounts, on: :create

  validates :name,
            presence: true,
            length:   {maximum: 200}
  validates :subdomain,
            presence:   true,
            format:     {with: SUBDOMAIN_FORMAT, allow_blank: true},
            exclusion:  {in: RESERVED_SUBDOMAINS},
            uniqueness: {case_sensitive: false}
  validates :min_amount_cents, :max_amount_cents,
            presence:     true,
            numericality: {only_integer: true, greater_than: 0}
  validate :currency_known
  validate :currency_unchanged, on: :update
  validate :max_amount_not_below_min

  # @private
  def to_param = subdomain

  private

  def currency_info = Money::Currency.find(currency)

  def apply_default_amounts
    return unless (info = currency_info)

    scale = (info.subunit_to_unit / 100r).ceil
    self.min_amount_cents ||= DEFAULT_MIN_AMOUNT_CENTS * scale
    self.max_amount_cents ||= DEFAULT_MAX_AMOUNT_CENTS * scale
  end

  def currency_known
    errors.add(:currency, :inclusion) unless currency_info
  end

  def currency_unchanged
    errors.add(:currency, :unchangeable) if currency_changed?
  end

  def max_amount_not_below_min
    return unless min_amount_cents && max_amount_cents
    return if max_amount_cents >= min_amount_cents

    errors.add(:max_amount_cents, :greater_than_or_equal_to, count: min_amount_cents)
  end
end
