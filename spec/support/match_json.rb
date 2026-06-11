# frozen_string_literal: true

RSpec::Matchers.define :match_json do |expected|
  match do |actual|
    @parsed = actual.kind_of?(String) ? JSON.parse(actual, symbolize_names: true) : actual
    values_match?(expected, @parsed)
  end

  failure_message do
    "expected JSON\n  #{@parsed.inspect}\nto match shape\n  #{expected.inspect}"
  end
end
