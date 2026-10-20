# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_21_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_identities", force: :cascade do |t|
    t.string "provider", null: false
    t.string "uid", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_account_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_account_identities_on_user_id"
  end

  create_table "account_jwt_refresh_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
    t.bigint "user_id", null: false
    t.index ["key"], name: "index_account_jwt_refresh_keys_on_key", unique: true
    t.index ["user_id"], name: "index_account_jwt_refresh_keys_on_user_id"
  end

  create_table "account_password_reset_keys", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
  end

  create_table "account_verification_keys", force: :cascade do |t|
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "key", null: false
    t.datetime "requested_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "account_webauthn_keys", primary_key: ["account_id", "webauthn_id"], force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "label"
    t.datetime "last_use", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.string "webauthn_id", null: false
  end

  create_table "account_webauthn_user_ids", force: :cascade do |t|
    t.string "webauthn_id", null: false
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "author_membership_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "market_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_membership_id"], name: "index_comments_on_author_membership_id"
    t.index ["market_id", "created_at"], name: "index_comments_on_market_id_and_created_at"
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.integer "max_amount_cents", null: false
    t.integer "min_amount_cents", null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.string "subdomain", null: false
    t.datetime "updated_at", null: false
    t.index "lower((subdomain)::text)", name: "index_groups_on_lower_subdomain", unique: true
    t.check_constraint "max_amount_cents >= min_amount_cents AND min_amount_cents > 0", name: "groups_amount_range_check"
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "group_id", null: false
    t.bigint "inviter_id", null: false
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index "group_id, lower((email)::text)", name: "index_invitations_on_group_and_email_open", unique: true, where: "(accepted_at IS NULL)"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "entry_type", null: false
    t.bigint "group_id", null: false
    t.bigint "market_id"
    t.bigint "membership_id", null: false
    t.bigint "position_id"
    t.bigint "reverses_entry_id"
    t.bigint "settlement_id"
    t.index ["group_id", "membership_id"], name: "index_ledger_entries_on_group_id_and_membership_id"
    t.index ["market_id"], name: "index_ledger_entries_on_market_id"
    t.index ["reverses_entry_id"], name: "index_ledger_entries_on_reverses_entry_id", unique: true
    t.index ["settlement_id"], name: "index_ledger_entries_on_settlement_id"
    t.check_constraint "amount_cents <> 0", name: "ledger_entries_amount_nonzero_check"
  end

  create_table "market_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_membership_id", null: false
    t.datetime "created_at", null: false
    t.bigint "market_id", null: false
    t.string "note"
    t.bigint "outcome_id"
    t.index ["market_id"], name: "index_market_events_on_market_id"
  end

  create_table "markets", force: :cascade do |t|
    t.datetime "closing_soon_notified_at"
    t.datetime "created_at", null: false
    t.bigint "creator_id", null: false
    t.text "description"
    t.bigint "group_id", null: false
    t.string "kind", default: "scheduled", null: false
    t.datetime "locks_at"
    t.bigint "oracle_id", null: false
    t.datetime "resolution_effective_at"
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.string "status", default: "open", null: false
    t.string "title", limit: 200, null: false
    t.datetime "updated_at", null: false
    t.bigint "winning_outcome_id"
    t.index ["group_id", "locks_at"], name: "index_markets_on_group_id_and_locks_at"
    t.index ["group_id", "status"], name: "index_markets_on_group_id_and_status"
    t.check_constraint "(kind::text = 'scheduled'::text) = (locks_at IS NOT NULL)", name: "markets_locks_at_matches_kind_check"
    t.check_constraint "(status::text = 'resolved'::text) = (winning_outcome_id IS NOT NULL)", name: "markets_resolved_iff_winning_outcome_check"
  end

  create_table "mcp_authorization_requests", force: :cascade do |t|
    t.string "identifier", null: false
    t.jsonb "parameters", null: false
    t.bigint "user_id"
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_mcp_authorization_requests_on_identifier", unique: true
    t.index ["user_id"], name: "index_mcp_authorization_requests_on_user_id"
  end

  create_table "mcp_connection_groups", force: :cascade do |t|
    t.bigint "mcp_connection_id", null: false
    t.bigint "group_id", null: false
    t.index ["group_id"], name: "index_mcp_connection_groups_on_group_id"
    t.index ["mcp_connection_id", "group_id"], name: "index_mcp_connection_groups_on_mcp_connection_id_and_group_id", unique: true
    t.index ["mcp_connection_id"], name: "index_mcp_connection_groups_on_mcp_connection_id"
  end

  create_table "mcp_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "application_id", null: false
    t.string "scopes", null: false
    t.string "resource", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "established_at"
    t.index ["application_id"], name: "index_mcp_connections_on_application_id"
    t.index ["user_id"], name: "index_mcp_connections_on_user_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.bigint "invited_by_id"
    t.string "role", default: "member", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["group_id", "status"], name: "index_memberships_on_group_id_and_status"
    t.index ["group_id", "user_id"], name: "index_memberships_on_group_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.bigint "mcp_connection_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["mcp_connection_id"], name: "index_oauth_access_grants_on_mcp_connection_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.bigint "mcp_connection_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in", null: false
    t.string "scopes", default: "", null: false
    t.string "previous_refresh_token", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["mcp_connection_id"], name: "index_oauth_access_tokens_on_mcp_connection_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "outcomes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "market_id", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["market_id", "name"], name: "index_outcomes_on_market_id_and_name", unique: true
    t.index ["market_id", "position"], name: "index_outcomes_on_market_id_and_position", unique: true
  end

  create_table "position_changes", force: :cascade do |t|
    t.bigint "amount_cents"
    t.datetime "created_at", null: false
    t.bigint "market_id", null: false
    t.bigint "membership_id", null: false
    t.bigint "outcome_id"
    t.index ["market_id", "created_at"], name: "index_position_changes_on_market_id_and_created_at"
    t.index ["market_id", "membership_id", "created_at"], name: "idx_on_market_id_membership_id_created_at_aafa81d315"
  end

  create_table "positions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.bigint "market_id", null: false
    t.bigint "membership_id", null: false
    t.bigint "outcome_id", null: false
    t.datetime "updated_at", null: false
    t.index ["market_id", "membership_id"], name: "index_positions_on_market_id_and_membership_id", unique: true
    t.index ["membership_id"], name: "index_positions_on_membership_id"
    t.index ["outcome_id"], name: "index_positions_on_outcome_id"
    t.check_constraint "amount_cents > 0", name: "positions_amount_positive_check"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "settlements", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.string "note"
    t.bigint "payee_membership_id", null: false
    t.bigint "payer_membership_id", null: false
    t.string "payment_method", null: false
    t.bigint "recorded_by_id", null: false
    t.datetime "updated_at", null: false
    t.datetime "voided_at"
    t.index ["group_id", "created_at"], name: "index_settlements_on_group_id_and_created_at"
    t.check_constraint "amount_cents > 0", name: "settlements_amount_positive_check"
  end

  create_table "users", force: :cascade do |t|
    t.string "cashapp_cashtag"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "locale"
    t.string "name", null: false
    t.jsonb "notification_preferences", default: {}, null: false
    t.string "password_hash"
    t.string "paypal_handle"
    t.datetime "push_prompt_dismissed_at"
    t.integer "status_id", default: 1, null: false
    t.boolean "superadmin", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "venmo_handle"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "account_identities", "users", on_delete: :cascade
  add_foreign_key "account_jwt_refresh_keys", "users", on_delete: :cascade
  add_foreign_key "account_password_reset_keys", "users", column: "id", on_delete: :cascade
  add_foreign_key "account_verification_keys", "users", column: "id", on_delete: :cascade
  add_foreign_key "account_webauthn_keys", "users", column: "account_id", on_delete: :cascade
  add_foreign_key "account_webauthn_user_ids", "users", column: "id", on_delete: :cascade
  add_foreign_key "comments", "markets"
  add_foreign_key "comments", "memberships", column: "author_membership_id"
  add_foreign_key "invitations", "groups"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "ledger_entries", "groups"
  add_foreign_key "ledger_entries", "ledger_entries", column: "reverses_entry_id"
  add_foreign_key "ledger_entries", "markets"
  add_foreign_key "ledger_entries", "memberships"
  add_foreign_key "ledger_entries", "positions"
  add_foreign_key "ledger_entries", "settlements"
  add_foreign_key "market_events", "markets"
  add_foreign_key "market_events", "memberships", column: "actor_membership_id"
  add_foreign_key "market_events", "outcomes"
  add_foreign_key "markets", "groups"
  add_foreign_key "markets", "memberships", column: "creator_id"
  add_foreign_key "markets", "memberships", column: "oracle_id"
  add_foreign_key "markets", "memberships", column: "resolved_by_id"
  add_foreign_key "markets", "outcomes", column: "winning_outcome_id", deferrable: :deferred
  add_foreign_key "mcp_authorization_requests", "users"
  add_foreign_key "mcp_connection_groups", "groups", on_delete: :cascade
  add_foreign_key "mcp_connection_groups", "mcp_connections", on_delete: :cascade
  add_foreign_key "mcp_connections", "oauth_applications", column: "application_id"
  add_foreign_key "mcp_connections", "users"
  add_foreign_key "memberships", "groups"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "users", column: "invited_by_id"
  add_foreign_key "oauth_access_grants", "mcp_connections"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id"
  add_foreign_key "oauth_access_tokens", "mcp_connections"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id"
  add_foreign_key "outcomes", "markets"
  add_foreign_key "position_changes", "markets"
  add_foreign_key "position_changes", "memberships"
  add_foreign_key "position_changes", "outcomes"
  add_foreign_key "positions", "markets"
  add_foreign_key "positions", "memberships"
  add_foreign_key "positions", "outcomes"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "settlements", "groups"
  add_foreign_key "settlements", "memberships", column: "payee_membership_id"
  add_foreign_key "settlements", "memberships", column: "payer_membership_id"
  add_foreign_key "settlements", "memberships", column: "recorded_by_id"
end
