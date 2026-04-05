# frozen_string_literal: true

module Undertow
  class Configuration
    # A Redis client or connection pool. Must respond to :sadd, :srem, :smembers,
    # :spop, :scard, :del. Injected by the host application:
    #
    #   Undertow.configure { |c| c.redis = Redis.new(url: ENV['REDIS_URL']) }
    #
    attr_accessor :redis

    # Maximum number of IDs to pop from the buffer per drain per model.
    attr_accessor :max_batch

    # ActiveJob queue to use for DrainJob.
    attr_accessor :queue_name

    def initialize
      @max_batch  = 1_000
      @queue_name = :undertow
    end

    def redis!
      redis or raise 'Undertow.configuration.redis is not set'
    end
  end
end
