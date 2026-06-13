# frozen_string_literal: true

module Undertow
  # ActiveRecord concern mixed in automatically when a model uses the Undertow DSL
  # (undertow_on_drain, undertow_skip, undertow_depends_on). Never included manually.
  #
  # Provides class-level callback registration and dependency push handlers, plus
  # instance-level self-tracking handlers. Callbacks are wired at boot by the Railtie
  # after all models are loaded.
  module Trackable
    extend ActiveSupport::Concern

    included do
      # Columns listed here suppress self-tracking when they are the *only*
      # things that changed, prevents feedback loops from columns updated by
      # the drain handler itself.
      class_attribute :_undertow_ignored_columns, default: [], instance_writer: false
    end

    class_methods do
      # Called by the Railtie after all models/associations are loaded.
      # Idempotent, safe to call multiple times (e.g. in reloading environments).
      def register_undertow_callbacks!(config)
        return if @_undertow_callbacks_registered

        @_undertow_callbacks_registered = true

        self._undertow_ignored_columns = config.skip_columns

        _register_self_callbacks!
        (config.dependencies || []).each { |dep| _register_dep_callbacks!(dep) }
      end

      def _push_undertow_pending(ids)
        Buffer.push_pending(name, ids)
      end

      def _push_undertow_deleted(ids)
        Buffer.push_deleted(name, ids)
      end

      def _push_dep_pending(record, dep)
        ids = _dep_ids_for(record, dep)
        _push_undertow_pending(ids) if ids.any?
      end

      def _push_dep_updated(record, dep)
        watched = dep[:watched_columns]
        # Two non-obvious cases where after_commit on :update fires:
        #   - no-op save: saved_changes is {}, suppressed when watched_columns is configured
        #   - touch (e.g. belongs_to touch: true): saved_changes contains only updated_at,
        #     suppressed only when watched_columns is configured and updated_at is not in it
        return if watched && (record.saved_changes.keys & watched).none?

        _push_dep_pending(record, dep)
      end

      private

      def _register_self_callbacks!
        after_commit  :_push_self_created, on: :create
        after_commit  :_push_self_updated, on: :update
        after_destroy :_push_self_deleted
        after_restore :_push_self_restored if respond_to?(:after_restore)
      end

      def _register_dep_callbacks!(dep)
        dep_class = _resolve_dep_class(dep)
        root_class = self

        dep_class.after_commit(on: :create) { root_class._push_dep_pending(self, dep) }
        dep_class.after_commit(on: :update) { root_class._push_dep_updated(self, dep) }

        # Soft-delete gems fire run_callbacks(:destroy), triggering after_destroy, but
        # mark the record deleted via update_columns (bypassing after_commit),
        # so the create/update callbacks above never double-fire on a soft delete.
        dep_class.after_destroy { root_class._push_dep_pending(self, dep) }

        # Soft-delete restores use update_columns to unmark the record, bypassing
        # after_commit. after_restore is the only hook that fires for restores.
        dep_class.after_restore { root_class._push_dep_pending(self, dep) } if dep_class.respond_to?(:after_restore)
      end

      def _resolve_dep_class(dep)
        reflect_on_association(dep[:association])&.klass ||
          dep[:association].to_s.classify.constantize
      end

      def _dep_ids_for(record, dep)
        if dep[:resolver]
          dep[:resolver].call(record).pluck(:id)
        else
          where(dep[:foreign_key] => record.id).pluck(:id)
        end
      end
    end

    private

    def _push_self_created
      _enqueue_self_pending
    end

    def _push_self_updated
      return unless _self_update_requires_invalidation?

      _enqueue_self_pending
    end

    def _push_self_restored
      _enqueue_self_pending
    end

    def _push_self_deleted
      self.class._push_undertow_deleted([id])
    end

    def _enqueue_self_pending
      self.class._push_undertow_pending([id])
    end

    def _self_update_requires_invalidation?
      changed = saved_changes.keys
      return false if changed.empty?

      ignored = self.class._undertow_ignored_columns
      (changed - ignored).any?
    end
  end
end
