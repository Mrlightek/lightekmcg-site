# frozen_string_literal: true
Money.rounding_mode  = BigDecimal::ROUND_HALF_UP
Money.locale_backend = :currency
Money.default_currency = "usd"
