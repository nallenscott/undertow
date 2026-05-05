# frozen_string_literal: true

RSpec.describe Undertow do
  describe '.without_tracking' do
    it 'suppresses buffer pushes inside the block' do
      Undertow.without_tracking { Undertow::Buffer.push_pending('Post', [1]) }

      expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
    end

    it 'resumes tracking after the block exits' do
      Undertow.without_tracking { }
      Undertow::Buffer.push_pending('Post', [1])

      expect(Undertow::Buffer.pop_pending('Post', 10)).not_to be_empty
    end

    it 'keeps tracking disabled when nested blocks exit' do
      Undertow.without_tracking do
        Undertow.without_tracking { }
        Undertow::Buffer.push_pending('Post', [1])
      end

      expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
    end

    it 'resumes tracking after outer block exits following nested block' do
      Undertow.without_tracking { Undertow.without_tracking { } }
      Undertow::Buffer.push_pending('Post', [1])

      expect(Undertow::Buffer.pop_pending('Post', 10)).not_to be_empty
    end
  end

  describe '.tick' do
    it 'skips enqueue when there is no pending work' do
      expect(Undertow::DrainJob).not_to receive(:perform_later)

      Undertow.tick
    end

    it 'skips enqueue when the lock is already held' do
      Undertow::Buffer.push_pending('Post', [1])
      allow(Undertow.configuration.store).to receive(:lock_acquire).and_return(false)

      expect(Undertow::DrainJob).not_to receive(:perform_later)

      Undertow.tick
    end

    it 'enqueues DrainJob when there is pending work and the lock is free' do
      Undertow::Buffer.push_pending('Post', [1])

      expect(Undertow::DrainJob).to receive(:perform_later)

      Undertow.tick
    end
  end
end
