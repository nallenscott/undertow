# frozen_string_literal: true

module Undertow
  # Class-level DSL extended onto ActiveRecord::Base by the Railtie. Any model
  # that calls these methods automatically registers itself with Undertow and
  # gets Trackable behavior wired in at boot — no include needed.
  #
  #   class Activity < ApplicationRecord
  #     undertow_on_drain ->(model_name, ids, deleted_ids) { ActivityReindexJob.perform_later(ids, deleted_ids) }
  #     undertow_skip     %w[lock_version searchkick_reindexing]
  #
  #     undertow_depends_on :provider, foreign_key: :provider_id, watched_columns: %w[approved mobile]
  #     undertow_depends_on :location_series,
  #                         resolver:        ->(ls) { Activity.where(series_id: ls.series_id) },
  #                         watched_columns: %w[location_id hidden]
  #   end
  #
  module DSL
    def undertow_on_drain(callable)
      _undertow_config.on_drain = callable
      _undertow_ensure_trackable!
    end

    def undertow_skip(columns)
      _undertow_config.skip_columns = columns
      _undertow_ensure_trackable!
    end

    def undertow_depends_on(association, foreign_key: nil, resolver: nil, watched_columns: nil)
      raise ArgumentError, 'provide exactly one of foreign_key: or resolver:' unless foreign_key.nil? ^ resolver.nil?

      _undertow_config.dependencies << {
        association:     association,
        foreign_key:     foreign_key,
        resolver:        resolver,
        watched_columns: watched_columns
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
