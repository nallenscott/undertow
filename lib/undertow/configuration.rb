# frozen_string_literal: true

module Undertow
  class Configuration
    # A store adapter (an instance of Undertow::Store::Base). Injected by the
    # host application:
    #
    #   # Redis
    #   Undertow.configure do |c|
    #     c.store = Undertow::Store::RedisStore.new(Redis.new(url: ENV['REDIS_URL']))
    #   end
    #

    #   # In-memory (test / single-process dev)
    #   Undertow.configure do |c|
    #     c.store = Undertow::Store::MemoryStore.new
    #   end
    #
    attr_accessor :store

    # Maximum number of IDs to pop from the buffer per drain per model.
    attr_accessor :max_batch

    # ActiveJob queue to use for DrainJob.
    attr_accessor :queue_name

    # Key used for the distributed drain lock. The scheduler acquires this lock
    # before enqueueing DrainJob; the job releases it immediately on start so
    # new work arriving mid-drain gets its own job on the next tick.
    # Set to nil to disable lock management entirely.
    attr_accessor :drain_lock_key

    def initialize
      @store          = Undertow::Store::MemoryStore.new
      @max_batch      = 1_000
      @queue_name     = :undertow
      @drain_lock_key = 'undertow:drain:lock'
    end

    def store!
      store or raise 'Undertow.configuration.store is not set'
    end
  end
end
