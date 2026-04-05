# frozen_string_literal: true

require 'active_support'
require 'active_record'

require_relative 'undertow/version'
require_relative 'undertow/configuration'
require_relative 'undertow/registry'
require_relative 'undertow/buffer'
require_relative 'undertow/dsl'
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
