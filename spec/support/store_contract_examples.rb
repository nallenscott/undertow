# frozen_string_literal: true

RSpec.shared_examples 'a Undertow store adapter' do
  let(:key) { 'undertow:test:set' }

  it 'adds and lists set members' do
    store.add_members(key, [1, 2, 3])

    expect(store.members(key).map(&:to_s)).to match_array(%w[1 2 3])
  end

  it 'removes a member from the set' do
    store.add_members(key, [1, 2, 3])
    store.remove_member(key, 2)

    expect(store.members(key).map(&:to_s)).to match_array(%w[1 3])
  end

  it 'pops up to count members from the set' do
    store.add_members(key, [1, 2, 3, 4])

    popped = store.pop_members(key, 2)

    expect(popped.length).to eq(2)
    expect(store.member_count(key)).to eq(2)
  end

  it 'returns [] when popping from an empty set' do
    expect(store.pop_members(key, 5)).to eq([])
  end

  it 'returns the set size' do
    store.add_members(key, [1, 2, 2])

    expect(store.member_count(key)).to eq(2)
  end

  it 'acquires and releases the drain lock' do
    expect(store.lock_acquire(lock_key, ttl: 10)).to be true
    expect(store.lock_acquire(lock_key, ttl: 10)).to eq(lock_reacquire_while_held)

    store.lock_release(lock_key)

    expect(store.lock_acquire(lock_key, ttl: 10)).to be true
  end
end
