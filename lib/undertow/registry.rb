# frozen_string_literal: true

module Undertow
  # Holds the declared dependency configuration for every tracked model.
  # Populated at class load time via the DSL (undertow_on_drain, undertow_skip,
  # undertow_depends_on); consumed by the Railtie and DrainJob.
  module Registry
    MODELS_KEY = 'undertow:pending:models'

    class ModelConfig
      attr_reader   :model_name, :dependencies
      attr_accessor :on_drain, :skip_columns

      def initialize(model_name)
        @model_name   = model_name
        @dependencies = []
        @skip_columns = []
        @on_drain     = nil
      end
    end

    class << self
      # Returns an existing config or creates a new one for model_name.
      # Called by each DSL macro the first time it fires on a model.
      def register(model_name)
        all[model_name] ||= ModelConfig.new(model_name)
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
