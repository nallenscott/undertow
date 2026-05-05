# frozen_string_literal: true

RSpec.describe Undertow::DrainJob do
  let(:drained) { [] }
  let(:config) do
    c = Undertow::Registry::ModelConfig.new('Widget')
    c.on_drain = ->(_model_name, ids, deleted_ids) { drained << { ids: ids, deleted_ids: deleted_ids } }
    c
  end

  before do
    Undertow::Registry.all['Widget'] = config
    Undertow::Buffer.acquire_drain_lock
  end

  after do
    Undertow::Registry.all.delete('Widget')
  end

  subject { described_class.new }

  describe '#perform' do
    it 'releases the drain lock immediately' do
      subject.perform

      # lock should be free, a second acquire should succeed
      expect(Undertow::Buffer.acquire_drain_lock).to be true
    end

    it 'returns early when no models are pending' do
      subject.perform

      expect(drained).to be_empty
    end

    it 'skips on_drain when model is in MODELS_KEY but both SETs are already empty' do
      Undertow::Buffer.reregister_model('Widget')

      subject.perform

      expect(drained).to be_empty
    end

    it 'drains pending and deleted IDs then calls on_drain' do
      Undertow::Buffer.push_pending('Widget', %w[1 2 3])
      Undertow::Buffer.push_deleted('Widget', %w[4])

      subject.perform

      expect(drained.length).to eq(1)
      expect(drained.first[:ids]).to match_array(%w[1 2 3])
      expect(drained.first[:deleted_ids]).to match_array(%w[4])
    end

    it 'clears both SETs after draining' do
      Undertow::Buffer.push_pending('Widget', %w[1 2])
      Undertow::Buffer.push_deleted('Widget', %w[3])

      subject.perform

      expect(Undertow::Buffer.remaining('Widget')).to eq(0)
    end

    it 'avoids orphaning IDs pushed concurrently between deregister and pop' do
      Undertow::Buffer.push_pending('Widget', ['1'])

      allow(Undertow::Buffer).to receive(:deregister_model).and_wrap_original do |original, name|
        original.call(name)
        Undertow::Buffer.push_pending('Widget', ['99'])
        Undertow::Buffer.reregister_model('Widget')
      end

      subject.perform

      expect(drained.first[:ids]).to include('99')
    end

    it 're-registers the model when the batch is capped' do
      Undertow.configuration.max_batch = 2
      Undertow::Buffer.push_pending('Widget', %w[1 2 3 4 5])

      subject.perform

      expect(Undertow::Buffer.remaining('Widget')).to eq(3)
      expect(Undertow::Buffer.pending_model_names).to include('Widget')
    end

    it 're-registers the model when the deleted SET batch is capped' do
      Undertow.configuration.max_batch = 2
      Undertow::Buffer.push_deleted('Widget', %w[1 2 3 4 5])

      subject.perform

      expect(Undertow::Buffer.remaining('Widget')).to eq(3)
      expect(Undertow::Buffer.pending_model_names).to include('Widget')
    end

    context 'when no config is registered for the model' do
      it 'restores IDs and re-registers the model in MODELS_KEY' do
        Undertow::Registry.all.delete('Widget')
        Undertow::Buffer.push_pending('Widget', %w[1 2])

        subject.perform

        expect(Undertow::Buffer.remaining('Widget')).to eq(2)
        expect(Undertow::Buffer.pending_model_names).to include('Widget')
      end
    end

    context 'when on_drain is nil' do
      before { config.on_drain = nil }

      it 'raises a descriptive error and restores IDs' do
        Undertow::Buffer.push_pending('Widget', %w[5 6])

        subject.perform

        expect(Undertow::Buffer.remaining('Widget')).to eq(2)
        expect(Undertow::Buffer.pending_model_names).to include('Widget')
      end
    end

    context 'when on_drain raises' do
      before { config.on_drain = ->(_m, _i, _d) { raise 'drain failure' } }

      it 'restores pending IDs and re-registers the model' do
        Undertow::Buffer.push_pending('Widget', %w[10 20])

        subject.perform

        expect(Undertow::Buffer.remaining('Widget')).to eq(2)
        expect(Undertow::Buffer.pending_model_names).to include('Widget')
      end

      it 'restores deleted IDs' do
        Undertow::Buffer.push_deleted('Widget', %w[99])

        subject.perform

        expect(Undertow::Buffer.remaining('Widget')).to eq(1)
      end

      it 'publishes error.undertow with the model name and exception' do
        Undertow::Buffer.push_pending('Widget', %w[1])

        payloads = []
        ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'error.undertow') do
          subject.perform
        end

        expect(payloads.first[:model]).to eq('Widget')
        expect(payloads.first[:exception]).to be_a(RuntimeError)
      end
    end

    it 'publishes drain.undertow after a successful on_drain call' do
      Undertow::Buffer.push_pending('Widget', %w[1 2])
      Undertow::Buffer.push_deleted('Widget', %w[3])

      payloads = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'drain.undertow') do
        subject.perform
      end

      expect(payloads.first[:model]).to eq('Widget')
      expect(payloads.first[:ids]).to match_array(%w[1 2])
      expect(payloads.first[:deleted_ids]).to match_array(%w[3])
    end
  end
end
