# frozen_string_literal: true

# Typed, explicitly enumerated assistant tools for everyday group participation.
module Mcp::Tools
  STRING = {type: "string"}.freeze
  ID = {type: "integer", minimum: 1}.freeze
  GROUP = {type: "string", description: "Group subdomain slug returned by list_groups."}.freeze
  AMOUNT = {type: "integer", minimum: 1, description: "Amount in the group's currency minor units (USD cents)."}.freeze
  TIME = {type: "string", format: "date-time", description: "ISO 8601 timestamp including timezone."}.freeze

  # @return [Array<Class<MCP::Tool>>] the server's tool definitions.
  def self.all
    [
        tool("list_groups", "List groups explicitly authorized for this connection.", {}, []),
        tool("get_group", "Get group settings, currency, and your membership.", {group_id: GROUP}),
        tool("list_members", "List active members and membership IDs.", {group_id: GROUP}),
        tool("list_markets", "List markets in feed order; use offset and limit to page through results.",
             {group_id: GROUP, status: {type: "string", enum: %w[open locked resolved voided]},
              limit: {type: "integer", minimum: 1, maximum: 100}, offset: {type: "integer", minimum: 0}}, %w[group_id]),
        tool("get_market", "Get market outcomes, pools, positions, comments, payouts, and resolution history.",
             {group_id: GROUP, market_id: ID}),
        tool("get_balances", "Get realized group balances in currency minor units.", {group_id: GROUP}),
        tool("get_settlement_suggestions", "Suggest external payments to settle balances; does not make payments.", {group_id: GROUP}),
        tool("list_settlements", "List the 100 most recent recorded settlements, including voided ones.", {group_id: GROUP}),
        tool("create_market", "Create a market with ordered outcomes. Scheduled markets require locks_at; open_ended markets omit it.",
             {group_id: GROUP, title: STRING, description: STRING, oracle_id: ID,
              kind: {type: "string", enum: %w[scheduled open_ended]}, locks_at: TIME,
              outcomes: {type: "array", minItems: 2, items: STRING}}, %w[group_id title outcomes], write: true),
        tool("update_market", "Edit an open market as its creator or an admin; notifies other position holders.",
             {group_id: GROUP, market_id: ID, title: STRING, description: STRING, locks_at: TIME},
             %w[group_id market_id], write: true, destructive: true),
        tool("set_position", "Place or replace your single position while trading is open. Amount is the total position, not an increment.",
             {group_id: GROUP, market_id: ID, outcome_id: ID, amount_cents: AMOUNT}, nil, write: true, destructive: true),
        tool("cancel_position", "Cancel your position while trading is open.", {group_id: GROUP, market_id: ID}, nil, write: true, destructive: true),
        tool("post_comment", "Post a comment to a market and notify members.", {group_id: GROUP, market_id: ID, body: STRING}, nil, write: true),
        tool("delete_comment", "Delete a comment as its author or a group admin.",
             {group_id: GROUP, market_id: ID, comment_id: ID}, nil, write: true, destructive: true),
        tool("resolve_market", "Resolve a market as oracle or admin. Early scheduled resolution requires effective_at, excluding later bets.",
             {group_id: GROUP, market_id: ID, outcome_id: ID, effective_at: TIME}, %w[group_id market_id outcome_id], write: true, destructive: true),
        tool("void_market", "Void a market as oracle or admin, reversing any resolution ledger entries.",
             {group_id: GROUP, market_id: ID}, nil, write: true, destructive: true),
        tool("record_settlement", "Record an external payment already made. Does not send money. You must be a party or group admin.",
             {group_id: GROUP, payer_membership_id: ID, payee_membership_id: ID, amount_cents: AMOUNT, payment_method: STRING, note: STRING},
             %w[group_id payee_membership_id amount_cents], write: true),
        tool("void_settlement", "Void a mistaken settlement you are a party to, or as admin; preserves history and reverses ledger entries.",
             {group_id: GROUP, settlement_id: ID}, nil, write: true, destructive: true)
    ]
  end

  def self.tool(name, description, properties, required=nil, write: false, destructive: false)
    MCP::Tool.define(name:, description:,
                     input_schema: {type: "object", properties:, required: required || properties.keys.map(&:to_s), additionalProperties: false},
                     annotations: {read_only_hint: !write, destructive_hint: destructive, idempotent_hint: !write, open_world_hint: false}) do |server_context:, **arguments|
      server_context.call(name, arguments, write:)
    end
  end
  private_class_method :tool
end
