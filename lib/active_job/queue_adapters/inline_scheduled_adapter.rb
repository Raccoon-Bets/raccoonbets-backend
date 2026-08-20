# frozen_string_literal: true

module ActiveJob
  module QueueAdapters
    # Executes jobs synchronously on the enqueueing thread, like {InlineAdapter},
    # and additionally accepts scheduled (`set(wait_until:)`) enqueues by running
    # them immediately rather than raising.
    #
    # {InlineAdapter#enqueue_at} raises NotImplementedError, so in an environment
    # with no queueing backend any request that schedules future work fails with a
    # 500. Jobs scheduled that way re-check their preconditions when they run (see
    # {Notifications::ClosingSoonNotifyJob}), so running one ahead of its timestamp
    # is a no-op rather than a premature notification.
    #
    # Synchronous execution is what makes `deliver_later` mail observable in
    # ActionMailer::Base.deliveries by the time a request returns.
    class InlineScheduledAdapter < InlineAdapter
      # @param job [ActiveJob::Base] the job to run
      # @param _timestamp [Float] the epoch time the job was scheduled for, ignored
      def enqueue_at(job, _timestamp) = enqueue(job)
    end
  end
end
