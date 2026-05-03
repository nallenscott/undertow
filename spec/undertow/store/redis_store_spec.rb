# frozen_string_literal: true

require 'redis'

RSpec.describe Undertow::Store::RedisStore, store: :redis do
  let(:redis_client) { Redis.new(url: ENV.fetch('UNDERTOW_TEST_REDIS_URL', 'redis://127.0.0.1:6379/15')) }
  let(:store) { described_class.new(redis_client) }
  let(:lock_key) { 'undertow:test:lock' }
  let(:lock_reacquire_while_held) { false }

  before do
    skip 'Set RUN_REDIS_SPECS=1 to run Redis adapter specs' unless ENV['RUN_REDIS_SPECS'] == '1'

    redis_client.flushdb
  end

  after do
    redis_client.flushdb
  rescue StandardError
    nil
  end

  it_behaves_like 'a Undertow store adapter'

  describe 'connection pool support' do
    it 'uses #with when the client responds to it' do
      pool = double('pool')
      allow(pool).to receive(:with).and_yield(redis_client)

      pooled = described_class.new(pool)
      pooled.add_members('undertow:test:pooled', [1])

      expect(redis_client.smembers('undertow:test:pooled')).to include('1')
    end
  end
end
