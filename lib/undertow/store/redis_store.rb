# frozen_string_literal: true

module Undertow
  module Store
    # Store adapter backed by Redis.
    #
    # Accepts a Redis client or a connection pool (any object responding to #with).
    #
    #   Undertow.configure do |c|
    #     c.store = Undertow::Store::RedisStore.new(Redis.new(url: ENV['REDIS_URL']))
    #   end
    #
    class RedisStore < Base
      def initialize(client)
        super()
        @client = client
      end

      def add_members(key, members)
        with_redis { |r| r.sadd(key, members) }
      end

      def remove_member(key, member)
        with_redis { |r| r.srem(key, member) }
      end

      def members(key)
        with_redis { |r| r.smembers(key) } || []
      end

      def pop_members(key, count)
        with_redis { |r| r.spop(key, count) } || []
      end

      def member_count(key)
        with_redis { |r| r.scard(key) } || 0
      end

      def lock_acquire(key, ttl:)
        with_redis { |r| r.set(key, '1', nx: true, ex: ttl) } || false
      end

      def lock_release(key)
        with_redis { |r| r.del(key) }
      end

      private

      def with_redis
        if @client.respond_to?(:with)
          @client.with { |conn| yield conn }
        else
          yield @client
        end
      rescue Redis::BaseConnectionError, Redis::CommandError => e
        Rails.logger.error("Undertow: Redis error: #{e.message}") if defined?(Rails)
        nil
      end
    end
  end
end
