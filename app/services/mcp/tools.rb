# frozen_string_literal: true

# The assistant tools the MCP server declares, each a typed, explicitly
# enumerated member action. Every tool hands its arguments to the request's
# {Mcp::ToolContext}, which checks consent and dispatches it to
# {Mcp::GroupTools}. Write tools are declared only to connections granted
# `mcp:write`.

module Mcp::Tools
  STRING = {type: "string"}.freeze
  ID = {type: "integer", minimum: 1}.freeze
  GROUP = {type: "string", description: "Group subdomain slug returned by list_groups."}.freeze
  AMOUNT = {type: "integer", minimum: 1,
            description: "Amount in minor units of the group currency (see get_group)."}.freeze
  TIME = {type: "string", format: "date-time", description: "ISO 8601 timestamp including timezone."}.freeze

  # Defines a tool whose schema rejects undeclared arguments. Every property is
  # required unless `required` lists a subset.
  def self.tool(name, description, properties, required: properties.keys, write: false, destructive: false)
    MCP::Tool.define(name:, description:,
                     input_schema: {type: "object", properties:, required: required.map(&:to_s), additionalProperties: false},
                     annotations:  {read_only_hint: !write, destructive_hint: destructive, idempotent_hint: !write,
                                    open_world_hint: false}) do |server_context:, **arguments|
      server_context.call(name, arguments, write:)
    end
  end
  private_class_method :tool

  # Tools that only read data the connection's groups can see.
  READ = [
      tool("list_groups", "List groups explicitly authorized for this connection.", {}),
      tool("get_group", "Get group settings, currency, and your membership.", {group_id: GROUP}),
      tool("list_members", "List active members and membership IDs.", {group_id: GROUP}),
      tool("list_markets", "List markets in feed order; use offset and limit to page through results.",
           {group_id: GROUP, status: {type: "string", enum: %w[open locked resolved voided]},
            limit: {type: "integer", minimum: 1, maximum: 100}, offset: {type: "integer", minimum: 0}},
           required: %i[group_id]),
      tool("get_market", "Get market outcomes, pools, positions, comments, payouts, and resolution history.",
           {group_id: GROUP, market_id: ID}),
      tool("get_balances", "Get realized group balances in minor units of the group currency.", {group_id: GROUP}),
      tool("get_settlement_suggestions", "Suggest external payments to settle balances; does not make payments.",
           {group_id: GROUP}),
      tool("list_settlements", "List the 100 most recent recorded settlements, including voided ones.", {group_id: GROUP})
  ].freeze

  # Tools that act on the member's behalf.
  WRITE = [
      tool("create_market", "Create a market with ordered outcomes. Scheduled markets require locks_at; open_ended markets omit it.",
           {group_id: GROUP, title: STRING, description: STRING, oracle_id: ID,
            kind: {type: "string", enum: %w[scheduled open_ended]}, locks_at: TIME,
            outcomes: {type: "array", minItems: 2, items: STRING}},
           required: %i[group_id title outcomes], write: true),
      tool("update_market", "Edit an open market as its creator or an admin; notifies other position holders.",
           {group_id: GROUP, market_id: ID, title: STRING, description: STRING, locks_at: TIME},
           required: %i[group_id market_id], write: true, destructive: true),
      tool("set_position", "Place or replace your single position while trading is open. Amount is the total position, not an increment.",
           {group_id: GROUP, market_id: ID, outcome_id: ID, amount_cents: AMOUNT}, write: true, destructive: true),
      tool("cancel_position", "Cancel your position while trading is open.",
           {group_id: GROUP, market_id: ID}, write: true, destructive: true),
      tool("post_comment", "Post a comment to a market and notify members.",
           {group_id: GROUP, market_id: ID, body: STRING}, write: true),
      tool("delete_comment", "Delete a comment as its author or a group admin.",
           {group_id: GROUP, market_id: ID, comment_id: ID}, write: true, destructive: true),
      tool("resolve_market", "Resolve a market as oracle or admin. Early scheduled resolution requires effective_at, excluding later bets.",
           {group_id: GROUP, market_id: ID, outcome_id: ID, effective_at: TIME},
           required: %i[group_id market_id outcome_id], write: true, destructive: true),
      tool("void_market", "Void a market as oracle or admin, reversing any resolution ledger entries.",
           {group_id: GROUP, market_id: ID}, write: true, destructive: true),
      tool("record_settlement", "Record an external payment already made. Does not send money. You must be a party or group admin.",
           {group_id: GROUP, payer_membership_id: ID, payee_membership_id: ID, amount_cents: AMOUNT,
            payment_method: STRING, note: STRING},
           required: %i[group_id payee_membership_id amount_cents], write: true),
      tool("void_settlement", "Void a mistaken settlement you are a party to, or as admin; preserves history and reverses ledger entries.",
           {group_id: GROUP, settlement_id: ID}, write: true, destructive: true)
  ].freeze

  # @param writable [Boolean] Whether the connection may act on the member's
  #   behalf.
  # @return [Array<Class<MCP::Tool>>] The tools to declare to the connection.

  def self.available(writable:) = writable ? READ + WRITE : READ
end
