# frozen_string_literal: true

RSpec.describe Undertow::DSL do
  # Gadget reuses the posts table — no schema changes needed.
  before do
    Object.const_set(:Gadget, Class.new(ActiveRecord::Base) { self.table_name = 'posts' })
  end

  after do
    Object.send(:remove_const, :Gadget)
    Undertow::Registry.all.delete('Gadget')
  end

  describe '.undertow_depends_on' do
    it 'raises ArgumentError when both foreign_key and resolver are provided' do
      expect {
        Gadget.undertow_depends_on(:author, foreign_key: :author_id, resolver: ->(_r) {})
      }.to raise_error(ArgumentError, /provide exactly one/)
    end

    it 'raises ArgumentError when neither foreign_key nor resolver is provided' do
      expect {
        Gadget.undertow_depends_on(:author)
      }.to raise_error(ArgumentError, /provide exactly one/)
    end

    it 'appends the dependency to the config' do
      Gadget.undertow_depends_on(:author, foreign_key: :author_id)

      dep = Undertow::Registry['Gadget'].dependencies.first
      expect(dep[:association]).to eq(:author)
      expect(dep[:foreign_key]).to eq(:author_id)
    end

    it 'freezes each dependency hash' do
      Gadget.undertow_depends_on(:author, foreign_key: :author_id)

      expect(Undertow::Registry['Gadget'].dependencies.first).to be_frozen
    end
  end

  describe 'Trackable auto-inclusion' do
    it 'includes Trackable when undertow_on_drain is called' do
      Gadget.undertow_on_drain ->(_m, _i, _d) {}

      expect(Gadget.ancestors).to include(Undertow::Trackable)
    end

    it 'includes Trackable when undertow_skip is called' do
      Gadget.undertow_skip %w[title]

      expect(Gadget.ancestors).to include(Undertow::Trackable)
    end

    it 'includes Trackable when undertow_depends_on is called' do
      Gadget.undertow_depends_on(:author, foreign_key: :author_id)

      expect(Gadget.ancestors).to include(Undertow::Trackable)
    end

    it 'includes Trackable only once regardless of how many macros are called' do
      Gadget.undertow_on_drain ->(_m, _i, _d) {}
      Gadget.undertow_skip %w[title]
      Gadget.undertow_depends_on(:author, foreign_key: :author_id)

      count = Gadget.ancestors.count { |a| a == Undertow::Trackable }
      expect(count).to eq(1)
    end
  end

  describe '.undertow_on_drain' do
    it 'sets on_drain on the config' do
      handler = ->(_m, _i, _d) {}
      Gadget.undertow_on_drain(handler)

      expect(Undertow::Registry['Gadget'].on_drain).to eq(handler)
    end
  end

  describe '.undertow_skip' do
    it 'sets skip_columns on the config' do
      Gadget.undertow_skip %w[title skipped]

      expect(Undertow::Registry['Gadget'].skip_columns).to eq(%w[title skipped])
    end
  end
end
