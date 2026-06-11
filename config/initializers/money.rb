# frozen_string_literal: true

require "money"

# The backend never formats money for display (the frontend does, via
# `Intl.NumberFormat`); the money gem is used only for ISO 4217 currency
# metadata (`Money::Currency`) and subunit math. Configure it explicitly so it
# never falls back to deprecated defaults or emits warnings.
Money.locale_backend = :i18n
Money.rounding_mode  = BigDecimal::ROUND_HALF_EVEN
