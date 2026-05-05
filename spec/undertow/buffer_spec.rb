# frozen_string_literal: true

class BufferSpecFakeStore < Undertow::Store::Base
  attr_reader :locks

  def initialize
    super
    @sets = Hash.new { |h, k| h[k] = Set.new }
    @locks = {}
    @lock_acquire_result_override = nil
  end

  def override_lock_acquire_result(value)
    @lock_acquire_result_override = value
  end

  def add_members(key, members)
    @sets[key].merge(Array(members))
  end

  def remove_member(key, member)
    @sets[key].delete(member)
  end

  def members(key)
    @sets[key].to_a
  end

  def pop_members(key, count)
    members = @sets[key].first(count)
    members.each { |m| @sets[key].delete(m) }
    members
  end

  def member_count(key)
    @sets[key].size
  end

  def lock_acquire(key, ttl:)
    return @lock_acquire_result_override unless @lock_acquire_result_override.nil?

    return false if @locks[key]

    @locks[key] = ttl
    true
  end

  def lock_release(key)
    @locks.delete(key)
  end
end

RSpec.describe Undertow::Buffer do
  let(:store) { BufferSpecFakeStore.new }

  before do
    Undertow.configure { |c| c.store = store }
  end

  describe '.push_pending' do
    it 'adds IDs to pending and registers the model' do
      described_class.push_pending('Post', [1, 2, 3])

      expect(described_class.pop_pending('Post', 10)).to match_array([1, 2, 3])
      expect(described_class.pending_model_names).to include('Post')
    end

    it 'is a no-op when tracking is disabled' do
      Undertow.without_tracking { described_class.push_pending('Post', [1]) }

      expect(described_class.pop_pending('Post', 10)).to be_empty
    end
  end

  describe '.push_deleted' do
    it 'adds IDs to deleted and registers the model' do
      described_class.push_deleted('Post', [4, 5])

      expect(described_class.pop_deleted('Post', 10)).to match_array([4, 5])
      expect(described_class.pending_model_names).to include('Post')
    end

    it 'is a no-op when tracking is disabled' do
      Undertow.without_tracking { described_class.push_deleted('Post', [1]) }

      expect(described_class.pop_deleted('Post', 10)).to be_empty
    end
  end

  describe '.remaining' do
    it 'returns the sum of pending and deleted set sizes' do
      described_class.push_pending('Post', [1, 2])
      described_class.push_deleted('Post', [3])

      expect(described_class.remaining('Post')).to eq(3)
    end
  end

  describe '.restore_pending / .restore_deleted' do
    it 'restores IDs only when arrays are non-empty' do
      described_class.restore_pending('Post', [])
      described_class.restore_deleted('Post', [])
      expect(described_class.remaining('Post')).to eq(0)

      described_class.restore_pending('Post', [1, 2])
      described_class.restore_deleted('Post', [3])
      expect(described_class.remaining('Post')).to eq(3)
    end
  end

  describe '.pending?' do
    it 'is false when no model names are registered and true otherwise' do
      expect(described_class.pending?).to be false

      described_class.push_pending('Post', [1])
      expect(described_class.pending?).to be true
    end
  end

  describe '.acquire_drain_lock / .release_drain_lock' do
    it 'delegates lock acquire/release through the configured store' do
      expect(described_class.acquire_drain_lock).to be true
      expect(described_class.acquire_drain_lock).to be false

      described_class.release_drain_lock
      expect(described_class.acquire_drain_lock).to be true
    end

    it 'passes ttl to lock_acquire' do
      described_class.acquire_drain_lock(ttl: 45)

      expect(store.locks[Undertow.configuration.drain_lock_key]).to eq(45)
    end

    it 'returns true without acquiring when drain_lock_key is nil' do
      Undertow.configuration.drain_lock_key = nil
      store.override_lock_acquire_result(false)

      expect(described_class.acquire_drain_lock).to be true
    end
  end
end
