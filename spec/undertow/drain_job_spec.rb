# frozen_string_literal: true

RSpec.describe Undertow::DrainJob do
  let(:redis)   { Undertow.configuration.redis }
  let(:drained) { [] }
  let(:config) do
    c = Undertow::Registry::ModelConfig.new('Widget')
    c.on_drain = ->(_model_name, ids, deleted_ids) { drained << { ids: ids, deleted_ids: deleted_ids } }
    c
  end

  before do
    Undertow::Registry.all['Widget'] = config
    redis.set(Undertow.configuration.drain_lock_key, '1', nx: true, ex: 30)
  end

  after do
    Undertow::Registry.all.delete('Widget')
  end

  subject { described_class.new }

  describe '#perform' do
    it 'releases the drain lock immediately' do
      subject.perform

      expect(redis.get(Undertow.configuration.drain_lock_key)).to be_nil
    end

    it 'returns early when no models are pending' do
      subject.perform

      expect(drained).to be_empty
    end

    it 'skips on_drain when model is in MODELS_KEY but both SETs are already empty' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
      # intentionally add no IDs to the pending or deleted SET

      subject.perform

      expect(drained).to be_empty
    end

    it 'drains pending and deleted IDs then calls on_drain' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
      redis.sadd('undertow:pending:Widget', %w[1 2 3])
      redis.sadd('undertow:deleted:Widget', %w[4])

      subject.perform

      expect(drained.length).to eq(1)
      expect(drained.first[:ids]).to match_array(%w[1 2 3])
      expect(drained.first[:deleted_ids]).to match_array(%w[4])
    end

    it 'clears both SETs after draining' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
      redis.sadd('undertow:pending:Widget', %w[1 2])
      redis.sadd('undertow:deleted:Widget', %w[3])

      subject.perform

      expect(redis.scard('undertow:pending:Widget')).to eq(0)
      expect(redis.scard('undertow:deleted:Widget')).to eq(0)
    end

    it 'deregisters the model before popping (race safety)' do
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
      redis.sadd('undertow:pending:Widget', ['1'])

      subject.perform

      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).not_to include('Widget')
    end

    it 're-registers the model when the batch is capped' do
      Undertow.configuration.max_batch = 2
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
      redis.sadd('undertow:pending:Widget', %w[1 2 3 4 5])

      subject.perform

      expect(redis.scard('undertow:pending:Widget')).to eq(3)
      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Widget')
    end

    it 're-registers the model when the deleted SET batch is capped' do
      Undertow.configuration.max_batch = 2
      redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
      redis.sadd('undertow:deleted:Widget', %w[1 2 3 4 5])

      subject.perform

      expect(redis.scard('undertow:deleted:Widget')).to eq(3)
      expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Widget')
    end

    context 'when no config is registered for the model' do
      it 'restores IDs and re-registers the model in MODELS_KEY' do
        Undertow::Registry.all.delete('Widget')
        redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
        redis.sadd('undertow:pending:Widget', %w[1 2])

        subject.perform

        expect(redis.smembers('undertow:pending:Widget')).to match_array(%w[1 2])
        expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Widget')
      end
    end

    context 'when on_drain is nil' do
      before { config.on_drain = nil }

      it 'raises a descriptive error and restores IDs' do
        redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
        redis.sadd('undertow:pending:Widget', %w[5 6])

        subject.perform

        expect(redis.smembers('undertow:pending:Widget')).to match_array(%w[5 6])
        expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Widget')
      end
    end

    context 'when on_drain raises' do
      before { config.on_drain = ->(_m, _i, _d) { raise 'drain failure' } }

      it 'restores pending IDs and re-registers the model' do
        redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
        redis.sadd('undertow:pending:Widget', %w[10 20])

        subject.perform

        expect(redis.smembers('undertow:pending:Widget')).to match_array(%w[10 20])
        expect(redis.smembers(Undertow::Registry::MODELS_KEY)).to include('Widget')
      end

      it 'restores deleted IDs' do
        redis.sadd(Undertow::Registry::MODELS_KEY, 'Widget')
        redis.sadd('undertow:deleted:Widget', %w[99])

        subject.perform

        expect(redis.smembers('undertow:deleted:Widget')).to include('99')
      end
    end
  end
end
