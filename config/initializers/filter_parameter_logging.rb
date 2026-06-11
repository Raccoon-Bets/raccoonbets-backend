# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
    passw email secret token _key crypt salt certificate otp ssn cvv cvc
]

# Web Push channel secrets arrive as nested request params (keys[auth] is a
# 16-byte bearer secret) that the partial matchers above don't catch. Filter the
# exact paths so they never reach the logs.
Rails.application.config.filter_parameters += ["keys.auth", "keys.p256dh"]
