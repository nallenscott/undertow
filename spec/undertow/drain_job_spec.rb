# frozen_string_literal: true

RSpec.describe Undertow::DrainJob do
  let(:drained) { [] }
  let(:config) do
    c = Undertow::Registry::ModelConfig.new('Widget')
    c.sinks[:test_sink] = {
      max_batch_size: nil,
      handler: ->(_model_name, upserted_ids, deleted_ids) {
        drained << { sink: :test_sink, upserted_ids: upserted_ids, deleted_ids: deleted_ids }
      }
    }
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

    it 'skips sinks when model is in MODELS_KEY but both SETs are already empty' do
      Undertow::Buffer.reregister_model('Widget')

      subject.perform

      expect(drained).to be_empty
    end

    it 'drains pending and deleted IDs then calls the sink handler' do
      Undertow::Buffer.push_pending('Widget', %w[1 2 3])
      Undertow::Buffer.push_deleted('Widget', %w[4])

      subject.perform

      expect(drained.length).to eq(1)
      expect(drained.first[:upserted_ids]).to match_array(%w[1 2 3])
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

      expect(drained.first[:upserted_ids]).to include('99')
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

    context 'when no sinks are configured' do
      before { config.sinks.clear }

      it 'raises a descriptive error and restores IDs' do
        Undertow::Buffer.push_pending('Widget', %w[5 6])

        subject.perform

        expect(Undertow::Buffer.remaining('Widget')).to eq(2)
        expect(Undertow::Buffer.pending_model_names).to include('Widget')
      end
    end

    context 'when a sink handler raises' do
      before do
        config.sinks[:test_sink] = { max_batch_size: nil, handler: ->(_m, _u, _d) { raise 'drain failure' } }
      end

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

      it 'publishes error.undertow with the model name, sink, and exception' do
        Undertow::Buffer.push_pending('Widget', %w[1])

        payloads = []
        ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'error.undertow') do
          subject.perform
        end

        expect(payloads.first[:model]).to eq('Widget')
        expect(payloads.first[:sink]).to eq(:test_sink)
        expect(payloads.first[:exception]).to be_a(RuntimeError)
      end
    end

    it 'publishes drain.undertow after a successful sink call' do
      Undertow::Buffer.push_pending('Widget', %w[1 2])
      Undertow::Buffer.push_deleted('Widget', %w[3])

      payloads = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'drain.undertow') do
        subject.perform
      end

      expect(payloads.first[:model]).to eq('Widget')
      expect(payloads.first[:sink]).to eq(:test_sink)
      expect(payloads.first[:upserted_ids]).to match_array(%w[1 2])
      expect(payloads.first[:deleted_ids]).to match_array(%w[3])
    end

    it 'includes a non-negative duration_ms in the drain.undertow payload' do
      Undertow::Buffer.push_pending('Widget', %w[1])

      payloads = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'drain.undertow') do
        subject.perform
      end

      expect(payloads.first[:duration_ms]).to be_a(Numeric)
      expect(payloads.first[:duration_ms]).to be >= 0
    end

    it 'measures the actual sink handler runtime' do
      config.sinks[:test_sink] = {
        max_batch_size: nil,
        handler: ->(_m, upserted_ids, deleted_ids) do
          sleep 0.02
          drained << { sink: :test_sink, upserted_ids: upserted_ids, deleted_ids: deleted_ids }
        end
      }
      Undertow::Buffer.push_pending('Widget', %w[1])

      payloads = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'drain.undertow') do
        subject.perform
      end

      expect(payloads.first[:duration_ms]).to be >= 15
    end

    context 'with multiple sinks' do
      before do
        config.sinks[:search_index] = {
          max_batch_size: nil,
          handler: ->(_m, upserted_ids, deleted_ids) {
            drained << { sink: :search_index, upserted_ids: upserted_ids, deleted_ids: deleted_ids }
          }
        }
        config.sinks[:kafka_topic] = {
          max_batch_size: nil,
          handler: ->(_m, upserted_ids, deleted_ids) {
            drained << { sink: :kafka_topic, upserted_ids: upserted_ids, deleted_ids: deleted_ids }
          }
        }
      end

      it 'calls every configured sink' do
        Undertow::Buffer.push_pending('Widget', %w[1 2])

        subject.perform

        expect(drained.map { |d| d[:sink] }).to match_array(%i[test_sink search_index kafka_topic])
      end

      it 'publishes drain.undertow once per sink' do
        Undertow::Buffer.push_pending('Widget', %w[1])

        payloads = []
        ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'drain.undertow') do
          subject.perform
        end

        expect(payloads.map { |p| p[:sink] }).to match_array(%i[test_sink search_index kafka_topic])
      end

      it 'does not couple the popped batch size to any sink max_batch_size' do
        config.sinks[:search_index][:max_batch_size] = 2
        Undertow.configuration.max_batch = 100
        Undertow::Buffer.push_pending('Widget', %w[1 2 3 4 5])

        subject.perform

        # The pop is sized by the global max_batch (100), not the search_index
        # sink's smaller limit (2), so all 5 IDs are popped and nothing remains.
        expect(Undertow::Buffer.remaining('Widget')).to eq(0)
      end

      it "chunks a sink's calls to its own max_batch_size without affecting other sinks" do
        config.sinks[:search_index][:max_batch_size] = 2
        Undertow.configuration.max_batch = 100
        Undertow::Buffer.push_pending('Widget', %w[1 2 3 4 5])

        subject.perform

        search_index_calls = drained.select { |d| d[:sink] == :search_index }
        other_calls        = drained.select { |d| d[:sink] != :search_index }

        expect(search_index_calls.length).to eq(3) # 5 IDs, chunked by 2 => 2, 2, 1
        expect(search_index_calls.flat_map { |c| c[:upserted_ids] }).to match_array(%w[1 2 3 4 5])
        expect(other_calls.length).to eq(2) # test_sink and kafka_topic, one call each
      end

      it 'restores the whole batch and retries every sink when one sink raises' do
        config.sinks[:kafka_topic] = { max_batch_size: nil, handler: ->(_m, _u, _d) { raise 'kafka down' } }
        Undertow::Buffer.push_pending('Widget', %w[1])

        subject.perform

        expect(Undertow::Buffer.remaining('Widget')).to eq(1)
        expect(Undertow::Buffer.pending_model_names).to include('Widget')
      end

      it 'tags error.undertow with the sink that raised' do
        config.sinks[:kafka_topic] = { max_batch_size: nil, handler: ->(_m, _u, _d) { raise 'kafka down' } }
        Undertow::Buffer.push_pending('Widget', %w[1])

        payloads = []
        ActiveSupport::Notifications.subscribed(->(*, payload) { payloads << payload }, 'error.undertow') do
          subject.perform
        end

        expect(payloads.first[:sink]).to eq(:kafka_topic)
      end
    end
  end
end
