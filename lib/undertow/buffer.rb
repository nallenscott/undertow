# frozen_string_literal: true

module Undertow
  # Low-level set operations used by Trackable callbacks and DrainJob.
  # Delegates to the configured store adapter. All methods are no-ops when
  # tracking is disabled.
  module Buffer
    class << self
      def push_pending(model_name, ids)
        return if Undertow.tracking_disabled?

        store.add_members(Registry.pending_key(model_name), ids)
        store.add_members(Registry::MODELS_KEY, model_name)
      end

      def push_deleted(model_name, ids)
        return if Undertow.tracking_disabled?

        store.add_members(Registry.deleted_key(model_name), ids)
        store.add_members(Registry::MODELS_KEY, model_name)
      end

      def pop_pending(model_name, count)
        store.pop_members(Registry.pending_key(model_name), count)
      end

      def pop_deleted(model_name, count)
        store.pop_members(Registry.deleted_key(model_name), count)
      end

      def pending_model_names
        store.members(Registry::MODELS_KEY)
      end

      def deregister_model(model_name)
        store.remove_member(Registry::MODELS_KEY, model_name)
      end

      def reregister_model(model_name)
        store.add_members(Registry::MODELS_KEY, model_name)
      end

      def remaining(model_name)
        store.member_count(Registry.pending_key(model_name)) +
          store.member_count(Registry.deleted_key(model_name))
      end

      def restore_pending(model_name, ids)
        store.add_members(Registry.pending_key(model_name), ids) if ids.any?
      end

      def restore_deleted(model_name, ids)
        store.add_members(Registry.deleted_key(model_name), ids) if ids.any?
      end

      def pending?
        store.member_count(Registry::MODELS_KEY).positive?
      end

      def acquire_drain_lock(ttl: 30)
        lock_key = Undertow.configuration.drain_lock_key
        return true unless lock_key

        store.lock_acquire(lock_key, ttl: ttl)
      end

      def release_drain_lock
        lock_key = Undertow.configuration.drain_lock_key
        return unless lock_key

        store.lock_release(lock_key)
      end

      private

      def store
        Undertow.configuration.store!
      end
    end
  end
end
