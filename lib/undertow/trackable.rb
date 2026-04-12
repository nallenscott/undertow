# frozen_string_literal: true

module Undertow
  # ActiveRecord concern mixed in automatically when a model uses the Undertow DSL
  # (undertow_on_drain, undertow_skip, undertow_depends_on). Never included manually.
  #
  # Provides class-level callback registration and the skip_columns guard.
  # Callbacks are wired at boot by the Railtie after all models are loaded.
  module Trackable
    extend ActiveSupport::Concern

    included do
      # Columns listed here suppress self-tracking when they are the *only*
      # things that changed — prevents feedback loops from columns updated by
      # the drain handler itself.
      class_attribute :_undertow_ignored_columns, default: [], instance_writer: false
    end

    class_methods do
      # Called by the Railtie after all models/associations are loaded.
      # Idempotent — safe to call multiple times (e.g. in reloading environments).
      def register_undertow_callbacks!(config)
        return if @_undertow_callbacks_registered

        @_undertow_callbacks_registered = true

        self._undertow_ignored_columns = config.skip_columns

        _register_self_callbacks!
        (config.dependencies || []).each { |dep| _register_dep_callbacks!(dep) }
      end

      private

      def _register_self_callbacks!
        after_commit  :_push_self_pending, on: %i[create update]
        after_destroy :_push_self_deleted
        after_restore :_push_self_pending if respond_to?(:after_restore)
      end

      def _register_dep_callbacks!(dep)
        dep_class = _resolve_dep_class(dep)
        return unless dep_class

        root_class = self
        watched    = dep[:watched_columns].presence # [] treated same as nil — watch all

        resolver = dep[:resolver] || begin
          fk = dep[:foreign_key]
          ->(record) { root_class.where(fk => record.id) }
        end

        push_pending = ->(record) {
          ids = resolver.call(record).pluck(:id)
          next unless ids.any?

          root_class._push_undertow_pending(ids)
        }

        # Skip create/update callback when watched_columns is set and none changed.
        # Note: saved_changes is empty when touched via belongs_to touch: true (bypasses
        # dirty tracking) — that correctly falls through to skip here.
        dep_class.after_commit on: %i[create update] do
          next if watched && (saved_changes.keys & watched).none?

          push_pending.call(self)
        end

        # Dep destroyed — reindex surviving root records. SoftDeletable calls
        # run_callbacks(:destroy), which fires after_destroy, but update_columns does NOT
        # trigger after_commit, so scoping after_commit to [:create, :update] above
        # ensures destroy commits don't double-fire.
        dep_class.after_destroy { push_pending.call(self) }

        # Dep restored — after_restore is the only hook that fires because restore!
        # uses update_columns, bypassing after_commit.
        if dep_class.respond_to?(:after_restore)
          dep_class.after_restore { push_pending.call(self) }
        end
      end

      def _resolve_dep_class(dep)
        if dep[:resolver]
          dep[:association].to_s.classify.constantize
        else
          reflect_on_association(dep[:association])&.klass ||
            dep[:association].to_s.classify.constantize
        end
      end

      public

      def _push_undertow_pending(ids)
        Buffer.push_pending(name, ids)
      end

      def _push_undertow_deleted(ids)
        Buffer.push_deleted(name, ids)
      end
    end

    private

    def _push_self_pending
      ignored = self.class._undertow_ignored_columns
      return if ignored.any? && saved_changes.any? && (saved_changes.keys - ignored).empty?

      self.class._push_undertow_pending([id])
    end

    def _push_self_deleted
      self.class._push_undertow_deleted([id])
    end
  end
end
