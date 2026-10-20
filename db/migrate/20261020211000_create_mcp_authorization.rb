# frozen_string_literal: true

# Stores OAuth clients, group-scoped connections, and hashed credentials.
class CreateMcpAuthorization < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, null: false, default: false
      t.timestamps
    end
    add_index :oauth_applications, :uid, unique: true

    create_table :mcp_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :application, null: false, foreign_key: {to_table: :oauth_applications}
      t.string :scopes, null: false
      t.string :resource, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    create_table :mcp_connection_groups do |t|
      t.references :mcp_connection, null: false, foreign_key: {on_delete: :cascade}
      t.references :group, null: false, foreign_key: {on_delete: :cascade}
    end
    add_index :mcp_connection_groups, %i[mcp_connection_id group_id], unique: true

    create_table :mcp_authorization_requests do |t|
      t.string :identifier, null: false
      t.jsonb :parameters, null: false
      t.references :user, foreign_key: true
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :mcp_authorization_requests, :identifier, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner, null: false, foreign_key: {to_table: :users}
      t.references :application, null: false, foreign_key: {to_table: :oauth_applications}
      t.references :mcp_connection, null: false, foreign_key: true
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_grants, :token, unique: true

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, null: false, foreign_key: {to_table: :users}
      t.references :application, null: false, foreign_key: {to_table: :oauth_applications}
      t.references :mcp_connection, null: false, foreign_key: true
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in, null: false
      t.string :scopes, null: false, default: ""
      t.string :previous_refresh_token, null: false, default: ""
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
  end
end
