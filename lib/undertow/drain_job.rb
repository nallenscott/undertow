# frozen_string_literal: true

module Undertow
  # Drains the per-model Redis buffers and delivers batches of dirty IDs to
  # each model's configured sinks.
  #
  # Publishes two ActiveSupport::Notifications events, once per sink (per chunk,
  # if a sink's max_batch_size is smaller than the popped batch):
  #   drain.undertow , after a successful sink call ({ model:, sink:, upserted_ids:, deleted_ids:, duration_ms: })
  #   error.undertow , when a sink raises ({ model:, sink:, exception: })
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

      config = Registry[model_name]
      raise "No Undertow config registered for #{model_name}" unless config
      raise "#{model_name} has no undertow_sink configured" if config.sinks.empty?

      # Deregister before popping, any concurrent push will re-add the model,
      # preventing the race where srem fires after a concurrent sadd.
      Buffer.deregister_model(model_name)

      upserted_ids = Buffer.pop_pending(model_name, max)
      deleted_ids  = Buffer.pop_deleted(model_name, max)
      return if upserted_ids.empty? && deleted_ids.empty?

      # If the batch was capped, re-register so the next scheduler tick picks up.
      Buffer.reregister_model(model_name) if Buffer.remaining(model_name).positive?

      current_sink = nil
      config.sinks.each do |sink_name, sink|
        current_sink = sink_name
        chunk_size   = sink[:max_batch_size] || max

        each_sink_chunk(upserted_ids, deleted_ids, chunk_size) do |chunk_upserted, chunk_deleted|
          duration_ms = measure_ms { sink[:handler].call(model_name, chunk_upserted, chunk_deleted) }

          ActiveSupport::Notifications.instrument('drain.undertow', {
            model: model_name,
            sink: sink_name,
            upserted_ids: chunk_upserted,
            deleted_ids: chunk_deleted,
            duration_ms: duration_ms
          })
        end
      end
    rescue StandardError => e
      Buffer.restore_pending(model_name, upserted_ids) if upserted_ids&.any?
      Buffer.restore_deleted(model_name, deleted_ids)  if deleted_ids&.any?
      Buffer.reregister_model(model_name)
      ActiveSupport::Notifications.instrument('error.undertow', { model: model_name, sink: current_sink, exception: e })
      Rails.logger.error("[Undertow::DrainJob] #{model_name}: #{e.message}") if defined?(Rails)
    end

    # Splits upserted_ids/deleted_ids into chunks of at most chunk_size combined
    # items, yielding each chunk as (chunk_upserted, chunk_deleted). Tags each ID
    # with which array it came from, concatenates into one list, slices that,
    # then splits each slice back apart, so a single chunk_size limit governs
    # the combined total regardless of the upserted/deleted split.
    def each_sink_chunk(upserted_ids, deleted_ids, chunk_size)
      tagged = upserted_ids.map { |id| [true, id] } + deleted_ids.map { |id| [false, id] }

      tagged.each_slice(chunk_size) do |slice|
        chunk_upserted, chunk_deleted = slice.partition { |upserted, _| upserted }
        yield chunk_upserted.map(&:last), chunk_deleted.map(&:last)
      end
    end

    def measure_ms
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
    end
  end
end
