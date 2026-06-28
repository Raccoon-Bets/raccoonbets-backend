# frozen_string_literal: true

# Solid Queue has been replaced by Sidekiq (Redis-backed), so its tables can be
# dropped. The execution tables reference solid_queue_jobs, so they drop first.
class DropSolidQueueTables < ActiveRecord::Migration[8.1]
  TABLES = %w[
      solid_queue_blocked_executions
      solid_queue_claimed_executions
      solid_queue_failed_executions
      solid_queue_ready_executions
      solid_queue_recurring_executions
      solid_queue_scheduled_executions
      solid_queue_jobs
      solid_queue_pauses
      solid_queue_processes
      solid_queue_recurring_tasks
      solid_queue_semaphores
  ].freeze

  def up
    TABLES.each { |table| drop_table table, if_exists: true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
