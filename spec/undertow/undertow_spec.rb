# frozen_string_literal: true

RSpec.describe Undertow do
  let(:redis) { Undertow.configuration.redis }

  describe '.without_tracking' do
    it 'suppresses buffer pushes inside the block' do
      Undertow.without_tracking { Undertow::Buffer.push_pending('Post', [1]) }

      expect(redis.scard('undertow:pending:Post')).to eq(0)
    end

    it 'resumes tracking after the block exits' do
      Undertow.without_tracking { }
      Undertow::Buffer.push_pending('Post', [1])

      expect(redis.scard('undertow:pending:Post')).to eq(1)
    end

    it 'keeps tracking disabled when nested blocks exit' do
      Undertow.without_tracking do
        Undertow.without_tracking { }
        Undertow::Buffer.push_pending('Post', [1])
      end

      expect(redis.scard('undertow:pending:Post')).to eq(0)
    end

    it 'resumes tracking after outer block exits following nested block' do
      Undertow.without_tracking { Undertow.without_tracking { } }
      Undertow::Buffer.push_pending('Post', [1])

      expect(redis.scard('undertow:pending:Post')).to eq(1)
    end
  end

  describe '.tick' do
    it 'does nothing when there is no pending work' do
      expect(Undertow::DrainJob).not_to receive(:perform_later)

      Undertow.tick
    end

    it 'does nothing when the lock is already held' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Post')
      Undertow::Buffer.acquire_drain_lock # hold the lock

      expect(Undertow::DrainJob).not_to receive(:perform_later)

      Undertow.tick
    end

    it 'enqueues DrainJob when there is pending work and the lock is free' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Post')

      expect(Undertow::DrainJob).to receive(:perform_later)

      Undertow.tick
    end
  end
end
