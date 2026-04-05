# frozen_string_literal: true

require 'active_support'
require 'active_record'

require_relative 'undertow/version'
require_relative 'undertow/configuration'
require_relative 'undertow/registry'
require_relative 'undertow/buffer'
require_relative 'undertow/trackable'
require_relative 'undertow/drain_job'
require_relative 'undertow/railtie' if defined?(Rails::Railtie)

module Undertow
  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Declare dependencies for a model. Called from the host application's
    # initializer. Accumulated declarations are wired into after_commit callbacks
    # at boot by the Railtie.
    #
    #   Undertow.track 'Activity', on_drain: ->(ids) { ActivityReindexJob.perform_later(ids) } do |t|
    #     t.depends_on :provider, foreign_key: :provider_id,
    #                             watched_columns: %w[approved mobile]
    #     t.depends_on :location_series,
    #                  resolver:        ->(ls) { Activity.where(series_id: ls.series_id) },
    #                  watched_columns: %w[location_id hidden]
    #   end
    #
    def track(model_name, on_drain:, &block)
      Registry.define(model_name, on_drain: on_drain, &block)
    end

    # Suppress all buffer pushes inside the block. Useful in tests and
    # data migrations where dependency callbacks should not fire.
    def without_tracking
      previous = Thread.current[:undertow_disabled]
      Thread.current[:undertow_disabled] = true
      yield
    ensure
      Thread.current[:undertow_disabled] = previous
    end

    def tracking_disabled?
      Thread.current[:undertow_disabled]
    end
  end
end
