# frozen_string_literal: true

require 'set'

module Undertow
  module Store
    # Store adapter backed by in-process memory.
    #
    # Uses Mutex-protected Ruby Sets for thread safety. Intended for use in
    # test environments and single-process development setups.
    #
    # Lock operations are no-ops, there is no scheduler race in a single process.
    #
    #   Undertow.configure do |c|
    #     c.store = Undertow::Store::MemoryStore.new
    #   end
    #
    # WARNING: State is not shared across processes. Do not use in multi-process
    # or multi-dyno deployments.
    class MemoryStore < Base
      def initialize
        super
        @sets  = Hash.new { |h, k| h[k] = Set.new }
        @mutex = Mutex.new
      end

      def add_members(key, members)
        @mutex.synchronize { @sets[key].merge(Array(members)) }
      end

      def remove_member(key, member)
        @mutex.synchronize { @sets[key].delete(member) }
      end

      def members(key)
        @mutex.synchronize { @sets[key].to_a }
      end

      def pop_members(key, count)
        @mutex.synchronize do
          members = @sets[key].first(count)
          members.each { |m| @sets[key].delete(m) }
          members
        end
      end

      def member_count(key)
        @mutex.synchronize { @sets[key].size }
      end

      # No-op, single process, no scheduler race possible.
      def lock_acquire(*)
        true
      end

      # No-op.
      def lock_release(key)
        # nothing to do
      end
    end
  end
end
