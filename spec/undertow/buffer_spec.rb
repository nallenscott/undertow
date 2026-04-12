# frozen_string_literal: true

RSpec.describe Undertow::Buffer do
  let(:redis) { Undertow.configuration.redis }

  describe '.push_pending' do
    it 'adds IDs to the pending SET and registers the model in MODELS_KEY' do
      described_class.push_pending('Post', [1, 2, 3])

      expect(redis.smembers('undertow:pending:Post')).to match_array(%w[1 2 3])
      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Post')
    end

    it 'is a no-op when tracking is disabled' do
      Undertow.without_tracking { described_class.push_pending('Post', [1]) }

      expect(redis.scard('undertow:pending:Post')).to eq(0)
    end

    it 'does not raise when Redis raises a connection error' do
      allow(redis).to receive(:sadd).and_raise(Redis::BaseConnectionError)

      expect { described_class.push_pending('Post', [1]) }.not_to raise_error
    end

    it 'raises when redis is not configured' do
      Undertow.configuration.redis = nil

      expect { described_class.push_pending('Post', [1]) }.to raise_error(RuntimeError, /redis is not set/)
    end
  end

  describe '.push_deleted' do
    it 'adds IDs to the deleted SET and registers the model' do
      described_class.push_deleted('Post', [4, 5])

      expect(redis.smembers('undertow:deleted:Post')).to match_array(%w[4 5])
      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Post')
    end

    it 'is a no-op when tracking is disabled' do
      Undertow.without_tracking { described_class.push_deleted('Post', [1]) }

      expect(redis.scard('undertow:deleted:Post')).to eq(0)
    end

    it 'does not raise when Redis raises a connection error' do
      allow(redis).to receive(:sadd).and_raise(Redis::BaseConnectionError)

      expect { described_class.push_deleted('Post', [1]) }.not_to raise_error
    end

    it 'raises when redis is not configured' do
      Undertow.configuration.redis = nil

      expect { described_class.push_deleted('Post', [1]) }.to raise_error(RuntimeError, /redis is not set/)
    end
  end

  describe '.pop_pending' do
    it 'removes and returns up to count IDs' do
      redis.sadd('undertow:pending:Post', %w[1 2 3 4 5])
      ids = described_class.pop_pending('Post', 3)

      expect(ids.length).to eq(3)
      expect(redis.scard('undertow:pending:Post')).to eq(2)
    end

    it 'returns [] when the SET is empty' do
      expect(described_class.pop_pending('Post', 10)).to eq([])
    end
  end

  describe '.pop_deleted' do
    it 'removes and returns IDs' do
      redis.sadd('undertow:deleted:Post', %w[7 8])

      expect(described_class.pop_deleted('Post', 10)).to match_array(%w[7 8])
      expect(redis.scard('undertow:deleted:Post')).to eq(0)
    end
  end

  describe '.pending_model_names' do
    it 'returns the names registered in MODELS_KEY' do
      redis.sadd(Undertow::Registry::MODELS_KEY, %w[Post Author])

      expect(described_class.pending_model_names).to match_array(%w[Post Author])
    end

    it 'returns [] when MODELS_KEY is empty' do
      expect(described_class.pending_model_names).to eq([])
    end
  end

  describe '.deregister_model / .reregister_model' do
    it 'removes and re-adds a model name from MODELS_KEY' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Post')

      described_class.deregister_model('Post')
      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).not_to include('Post')

      described_class.reregister_model('Post')
      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Post')
    end
  end

  describe '.remaining' do
    it 'returns the sum of pending and deleted SET sizes' do
      redis.sadd('undertow:pending:Post', %w[1 2])
      redis.sadd('undertow:deleted:Post', %w[3])

      expect(described_class.remaining('Post')).to eq(3)
    end

    it 'returns 0 when both SETs are empty' do
      expect(described_class.remaining('Post')).to eq(0)
    end
  end

  describe '.restore_pending / .restore_deleted' do
    it 'pushes IDs back into the pending SET' do
      described_class.restore_pending('Post', %w[1 2])

      expect(redis.smembers('undertow:pending:Post')).to match_array(%w[1 2])
    end

    it 'is a no-op when the pending ids array is empty' do
      described_class.restore_pending('Post', [])

      expect(redis.scard('undertow:pending:Post')).to eq(0)
    end

    it 'pushes IDs back into the deleted SET' do
      described_class.restore_deleted('Post', %w[3])

      expect(redis.smembers('undertow:deleted:Post')).to include('3')
    end

    it 'is a no-op when the deleted ids array is empty' do
      described_class.restore_deleted('Post', [])

      expect(redis.scard('undertow:deleted:Post')).to eq(0)
    end
  end

  describe '.pending?' do
    it 'returns false when MODELS_KEY is empty' do
      expect(described_class.pending?).to be false
    end

    it 'returns true when MODELS_KEY has entries' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Post')

      expect(described_class.pending?).to be true
    end
  end

  describe '.acquire_drain_lock / .release_drain_lock' do
    it 'acquires the lock and returns true' do
      expect(described_class.acquire_drain_lock).to be true
    end

    it 'returns false when the lock is already held' do
      described_class.acquire_drain_lock

      expect(described_class.acquire_drain_lock).to be false
    end

    it 'releases the lock so it can be re-acquired' do
      described_class.acquire_drain_lock
      described_class.release_drain_lock

      expect(described_class.acquire_drain_lock).to be true
    end

    it 'returns true without touching Redis when drain_lock_key is nil' do
      Undertow.configuration.drain_lock_key = nil

      expect(redis).not_to receive(:set)
      expect(described_class.acquire_drain_lock).to be true
    end
  end

  describe 'connection pool support' do
    it 'checks out a connection via #with when the client responds to it' do
      pool = double('pool')
      allow(pool).to receive(:with).and_yield(redis)
      Undertow.configuration.redis = pool

      described_class.push_pending('Post', [1])

      expect(redis.smembers('undertow:pending:Post')).to include('1')
    end
  end
end
