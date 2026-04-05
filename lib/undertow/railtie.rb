# frozen_string_literal: true

module Undertow
  class Railtie < Rails::Railtie
    # Extend ActiveRecord::Base with the Undertow DSL so any model can call
    # undertow_on_drain, undertow_skip, and undertow_depends_on in its class body.
    initializer 'undertow.extend_active_record' do
      ActiveSupport.on_load(:active_record) { extend Undertow::DSL }
    end

    # Wire after_commit callbacks onto every registered model and its dependencies
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
