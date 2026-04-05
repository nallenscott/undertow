# frozen_string_literal: true

module Undertow
  # Holds the declared dependency configuration for every tracked model.
  # Populated at app boot via Undertow.track; consumed by the Railtie and
  # DrainJob.
  module Registry
    MODELS_KEY = 'undertow:pending:models'

    class ModelConfig
      attr_reader :model_name, :dependencies, :on_drain

      def initialize(model_name, on_drain:)
        @model_name   = model_name
        @dependencies = []
        @on_drain     = on_drain
      end

      # DSL method called inside the Undertow.track block.
      #
      #   t.depends_on :provider, foreign_key: :provider_id,
      #                           watched_columns: %w[approved mobile]
      #
      #   t.depends_on :location_series,
      #                resolver:        ->(ls) { Activity.where(series_id: ls.series_id) },
      #                watched_columns: %w[location_id hidden]
      #
      def depends_on(association, foreign_key: nil, resolver: nil, watched_columns: nil)
        raise ArgumentError, 'provide exactly one of foreign_key: or resolver:' unless foreign_key.nil? ^ resolver.nil?

        @dependencies << {
          association:     association,
          foreign_key:     foreign_key,
          resolver:        resolver,
          watched_columns: watched_columns&.map(&:to_s)
        }.freeze
      end
    end

    class << self
      def define(model_name, on_drain:, &block)
        config = ModelConfig.new(model_name, on_drain: on_drain)
        block.call(config) if block
        all[model_name] = config
      end

      def all
        @all ||= {}
      end

      def [](model_name)
        all[model_name]
      end

      def key?(model_name)
        all.key?(model_name)
      end

      def pending_key(model_name) = "undertow:pending:#{model_name}"
      def deleted_key(model_name) = "undertow:deleted:#{model_name}"
    end
  end
end
