# frozen_string_literal: true

module Undertow
  # Low-level Redis SET operations used by Trackable callbacks and DrainJob.
  # All methods are no-ops when tracking is disabled or Redis is unavailable.
  module Buffer
    class << self
      def push_pending(model_name, ids)
        return if Undertow.tracking_disabled?

        with_redis do |r|
          r.sadd(Registry.pending_key(model_name), ids)
          r.sadd(Registry::MODELS_KEY, model_name)
        end
      end

      def push_deleted(model_name, ids)
        return if Undertow.tracking_disabled?

        with_redis do |r|
          r.sadd(Registry.deleted_key(model_name), ids)
          r.sadd(Registry::MODELS_KEY, model_name)
        end
      end

      def pop_pending(model_name, count)
        with_redis { |r| r.spop(Registry.pending_key(model_name), count) } || []
      end

      def pop_deleted(model_name, count)
        with_redis { |r| r.spop(Registry.deleted_key(model_name), count) } || []
      end

      def pending_model_names
        with_redis { |r| r.smembers(Registry::MODELS_KEY) } || []
      end

      def deregister_model(model_name)
        with_redis { |r| r.srem(Registry::MODELS_KEY, model_name) }
      end

      def reregister_model(model_name)
        with_redis { |r| r.sadd(Registry::MODELS_KEY, model_name) }
      end

      def remaining(model_name)
        with_redis do |r|
          r.scard(Registry.pending_key(model_name)) +
          r.scard(Registry.deleted_key(model_name))
        end || 0
      end

      def restore_pending(model_name, ids)
        with_redis { |r| r.sadd(Registry.pending_key(model_name), ids) } if ids.any?
      end

      def restore_deleted(model_name, ids)
        with_redis { |r| r.sadd(Registry.deleted_key(model_name), ids) } if ids.any?
      end

      def pending?
        with_redis { |r| r.scard(Registry::MODELS_KEY) > 0 } || false
      end

      # Acquire the distributed drain lock using SET NX. Returns true if the lock
      # was acquired, false if it was already held. TTL is a safety valve in case
      # the job process dies before releasing it.
      def acquire_drain_lock(ttl: 30)
        lock_key = Undertow.configuration.drain_lock_key
        return true unless lock_key

        with_redis { |r| r.set(lock_key, '1', nx: true, ex: ttl) } || false
      end

      # Release the drain lock. Called at the start of DrainJob#perform so the
      # scheduler can enqueue another job for IDs that arrive while this one runs.
      def release_drain_lock
        lock_key = Undertow.configuration.drain_lock_key
        return unless lock_key

        with_redis { |r| r.del(lock_key) }
      end

      private

      def with_redis
        yield Undertow.configuration.redis!
      rescue Redis::BaseConnectionError => e
        Rails.logger.error("Undertow: Redis unavailable: #{e.message}") if defined?(Rails)
        nil
      end
    end
  end
end
