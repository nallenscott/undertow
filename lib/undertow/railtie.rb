# frozen_string_literal: true

module Undertow
  class Railtie < Rails::Railtie
    # Wire after_commit callbacks onto every tracked model and its dependencies
    # after all models are loaded. Runs on each code reload in development.
    config.to_prepare do
      Registry.all.each do |model_name, config|
        model_name.constantize.register_undertow_callbacks!(config)
      rescue NameError => e
        Rails.logger.warn("[Undertow] Could not load #{model_name}: #{e.message}")
      end
    end
  end
end
