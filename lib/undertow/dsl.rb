# frozen_string_literal: true

module Undertow
  # Class-level DSL extended onto ActiveRecord::Base by the Railtie. Any model
  # that calls these methods automatically registers itself with Undertow and
  # gets Trackable behavior wired in at boot, no include needed.
  #
  #   class Post < ApplicationRecord
  #     undertow_on_drain ->(model_name, upserted_ids, deleted_ids) { PostSyncJob.perform_later(upserted_ids, deleted_ids) }
  #     undertow_skip     %w[view_count updated_at]
  #
  #     undertow_depends_on :author, foreign_key: :author_id, watched_columns: %w[name bio]
  #     undertow_depends_on :tag,
  #                         resolver:        ->(tag) { Post.joins(:post_tags).where(post_tags: { tag_id: tag.id }) },
  #                         watched_columns: %w[name slug]
  #   end
  #
  module DSL
    def undertow_on_drain(callable)
      _undertow_config.on_drain = callable
      _undertow_ensure_trackable!
    end

    # Suppress self-tracking when these root-model columns are the only changes.
    # Accepts strings or symbols; blanks are ignored.
    def undertow_skip(columns)
      _undertow_config.skip_columns = Array(columns).map(&:to_s).reject(&:blank?).uniq
      _undertow_ensure_trackable!
    end

    # Track invalidations from an upstream association.
    # `watched_columns` accepts strings or symbols; blanks are ignored.
    # Empty/nil means no watched-column filter.
    def undertow_depends_on(association, foreign_key: nil, resolver: nil, watched_columns: nil)
      raise ArgumentError, 'provide exactly one of foreign_key: or resolver:' unless foreign_key.nil? ^ resolver.nil?

      normalized_watched = Array(watched_columns).map(&:to_s).
        reject(&:blank?).uniq.presence

      _undertow_config.dependencies << {
         association: association,
         foreign_key: foreign_key,
         resolver: resolver,
         watched_columns: normalized_watched
      }.freeze
      _undertow_ensure_trackable!
    end

    private

    def _undertow_config
      Registry.register(name)
    end

    def _undertow_ensure_trackable!
      include Undertow::Trackable unless ancestors.include?(Undertow::Trackable)
    end
  end
end
