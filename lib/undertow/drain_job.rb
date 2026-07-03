# frozen_string_literal: true

module Undertow
  # Drains the per-model Redis buffers and delivers batches of dirty IDs to
  # each model's configured on_drain handler.
  #
  # Publishes two ActiveSupport::Notifications events:
  #   drain.undertow , after a successful on_drain call ({ model:, upserted_ids:, deleted_ids:, duration_ms: })
  #   error.undertow , when on_drain raises ({ model:, exception: })
  class DrainJob < ActiveJob::Base
    queue_as { Undertow.configuration.queue_name }

    def perform
      # Release the lock before draining so the scheduler can enqueue another job
      # for IDs that arrive while this one is running.
      Buffer.release_drain_lock

      model_names = Buffer.pending_model_names
      return if model_names.empty?

      model_names.each { |name| drain_model(name) }
    end

    private

    def drain_model(model_name)
      max = Undertow.configuration.max_batch

      # Deregister before popping, any concurrent push will re-add the model,
      # preventing the race where srem fires after a concurrent sadd.
      Buffer.deregister_model(model_name)

      upserted_ids = Buffer.pop_pending(model_name, max)
      deleted_ids  = Buffer.pop_deleted(model_name, max)
      return if upserted_ids.empty? && deleted_ids.empty?

      # If the batch was capped, re-register so the next scheduler tick picks up.
      Buffer.reregister_model(model_name) if Buffer.remaining(model_name).positive?

      config = Registry[model_name]
      raise "No Undertow config registered for #{model_name}" unless config
      raise "#{model_name} is missing undertow_on_drain" unless config.on_drain

      duration_ms = measure_ms { config.on_drain.call(model_name, upserted_ids, deleted_ids) }

      ActiveSupport::Notifications.instrument('drain.undertow', {
        model: model_name,
        upserted_ids: upserted_ids,
        deleted_ids: deleted_ids,
        duration_ms: duration_ms
      })
    rescue StandardError => e
      Buffer.restore_pending(model_name, upserted_ids) if upserted_ids&.any?
      Buffer.restore_deleted(model_name, deleted_ids)  if deleted_ids&.any?
      Buffer.reregister_model(model_name)
      ActiveSupport::Notifications.instrument('error.undertow', { model: model_name, exception: e })
      Rails.logger.error("[Undertow::DrainJob] #{model_name}: #{e.message}") if defined?(Rails)
    end

    def measure_ms
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
    end
  end
end
