# frozen_string_literal: true

RSpec.describe Undertow::Registry do
  # Use names that don't conflict with Post/Author registered in spec_helper.
  let(:name) { 'Widget' }

  after { described_class.all.delete(name) }

  describe '.register' do
    it 'creates a new ModelConfig for an unknown model name' do
      config = described_class.register(name)
      expect(config).to be_a(described_class::ModelConfig)
      expect(config.model_name).to eq(name)
    end

    it 'returns the same config on subsequent calls' do
      expect(described_class.register(name)).to be(described_class.register(name))
    end

    it 'initialises with empty dependencies and skip_columns and nil on_drain' do
      config = described_class.register(name)
      expect(config.dependencies).to eq([])
      expect(config.skip_columns).to eq([])
      expect(config.on_drain).to be_nil
    end
  end

  describe '.[]' do
    it 'returns nil for an unregistered model' do
      expect(described_class['Unknown']).to be_nil
    end

    it 'returns the config for a registered model' do
      described_class.register(name)
      expect(described_class[name]).to be_a(described_class::ModelConfig)
    end
  end

  describe '.key?' do
    it 'returns false for an unregistered model' do
      expect(described_class.key?('Unknown')).to be false
    end

    it 'returns true for a registered model' do
      described_class.register(name)
      expect(described_class.key?(name)).to be true
    end
  end

  describe '.pending_key / .deleted_key' do
    it 'returns namespaced Redis keys' do
      expect(described_class.pending_key('Post')).to eq('undertow:pending:Post')
      expect(described_class.deleted_key('Post')).to eq('undertow:deleted:Post')
    end
  end

  describe 'ModelConfig' do
    subject(:config) { described_class::ModelConfig.new(name) }

    it 'accumulates dependencies' do
      dep = { association: :author, foreign_key: :author_id, resolver: nil, watched_columns: nil }.freeze
      config.dependencies << dep
      expect(config.dependencies).to include(dep)
    end

    it 'allows on_drain and skip_columns to be set' do
      callable = ->(_model_name, _ids, _deleted_ids) {}
      config.on_drain = callable
      config.skip_columns = %w[lock_version]

      expect(config.on_drain).to be(callable)
      expect(config.skip_columns).to eq(%w[lock_version])
    end
  end
end
