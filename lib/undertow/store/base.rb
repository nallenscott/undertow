# frozen_string_literal: true

module Undertow
  module Store
    # Abstract base class for Undertow store adapters.
    #
    # Concrete adapters must implement all methods defined here.
    # Buffer delegates all operations to the configured store, so adapters
    # are the only place that knows about the underlying backend.
    class Base
      # Add members to the set at key.
      def add_members(key, members)
        raise NotImplementedError, "#{self.class}#add_members is not implemented"
      end

      # Remove a single member from the set at key.
      def remove_member(key, member)
        raise NotImplementedError, "#{self.class}#remove_member is not implemented"
      end

      # Return all members of the set at key.
      def members(key)
        raise NotImplementedError, "#{self.class}#members is not implemented"
      end

      # Atomically remove and return up to count members from the set at key.
      def pop_members(key, count)
        raise NotImplementedError, "#{self.class}#pop_members is not implemented"
      end

      # Return the number of members in the set at key.
      def member_count(key)
        raise NotImplementedError, "#{self.class}#member_count is not implemented"
      end

      # Attempt to acquire a lock at key with the given TTL in seconds.
      # Returns true if the lock was acquired, false if already held.
      def lock_acquire(key, ttl:)
        raise NotImplementedError, "#{self.class}#lock_acquire is not implemented"
      end

      # Release the lock at key.
      def lock_release(key)
        raise NotImplementedError, "#{self.class}#lock_release is not implemented"
      end
    end
  end
end
