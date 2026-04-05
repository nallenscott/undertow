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
