# frozen_string_literal: true

module Undertow
  # ActiveRecord concern included in any model that participates as a tracked
  # root model. Provides class-level callback registration and the
  # _enrichment_ignored_columns guard.
  #
  #   class Activity < ApplicationRecord
  #     include Undertow::Trackable
  #   end
  #
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

        self._undertow_ignored_columns = (config[:skip_columns] || []).map(&:to_s)

        _register_self_callbacks!
        (config.dependencies || []).each { |dep| _register_dep_callbacks!(dep) }
      end

      private

      def _register_self_callbacks!
        after_commit  :_push_self_pending, on: %i[create update]
        after_destroy :_push_self_deleted

        if method_defined?(:restore)
          after_restore :_push_self_pending
        end
      end

      def _register_dep_callbacks!(dep)
        dep_class = dep[:association].to_s.classify.safe_constantize
        return unless dep_class

        root_class  = self
        foreign_key = dep[:foreign_key]
        resolver    = dep[:resolver]
        watched     = dep[:watched_columns]

        dep_class.after_commit(on: %i[create update]) do
          next if watched && (saved_changes.keys & watched).empty?

          ids = if foreign_key
            root_class.where(foreign_key => id).pluck(:id)
          else
            resolver.call(self).pluck(:id)
          end

          root_class._push_undertow_pending(ids) if ids.any?
        end

        dep_class.after_destroy do
          ids = if foreign_key
            root_class.where(foreign_key => id).pluck(:id)
          else
            resolver.call(self).pluck(:id)
          end

          root_class._push_undertow_pending(ids) if ids.any?
        end

        if dep_class.method_defined?(:restore)
          dep_class.after_restore do
            ids = if foreign_key
              root_class.where(foreign_key => id).pluck(:id)
            else
              resolver.call(self).pluck(:id)
            end

            root_class._push_undertow_pending(ids) if ids.any?
          end
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
      changed = previous_changes.keys
      ignored = self.class._undertow_ignored_columns

      return if changed.any? && (changed - ignored).empty?

      self.class._push_undertow_pending([id])
    end

    def _push_self_deleted
      self.class._push_undertow_deleted([id])
    end
  end
end
