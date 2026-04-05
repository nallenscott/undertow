# frozen_string_literal: true

module Undertow
  # Drains the per-model Redis buffers and delivers batches of dirty IDs to
  # each model's configured on_drain handler.
  #
  # The host application subclasses this or uses it directly:
  #
  #   class UndertowDrainJob < Undertow::DrainJob; end
  #
  # Enqueue it on a scheduler tick when Buffer.pending? is true.
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

      # Deregister before popping — any concurrent push will re-add the model,
      # preventing the race where srem fires after a concurrent sadd.
      Buffer.deregister_model(model_name)

      ids         = Buffer.pop_pending(model_name, max)
      deleted_ids = Buffer.pop_deleted(model_name, max)
      return if ids.empty? && deleted_ids.empty?

      # If the batch was capped, re-register so the next scheduler tick picks up.
      Buffer.reregister_model(model_name) if Buffer.remaining(model_name).positive?

      config = Registry[model_name]
      raise "No Undertow config registered for #{model_name}" unless config
      config.on_drain.call(model_name, ids, deleted_ids)
    rescue StandardError => e
      Buffer.restore_pending(model_name, ids)         if ids&.any?
      Buffer.restore_deleted(model_name, deleted_ids) if deleted_ids&.any?
      Buffer.reregister_model(model_name)
      Rails.logger.error("[Undertow::DrainJob] #{model_name}: #{e.message}") if defined?(Rails)
    end
  end
end
