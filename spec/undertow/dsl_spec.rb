# frozen_string_literal: true

RSpec.describe Undertow::DSL do
  # Gadget reuses the posts table, no schema changes needed.
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

    it 'normalizes watched_columns to unique, non-blank strings' do
      Gadget.undertow_depends_on(
        :author,
        foreign_key: :author_id,
        watched_columns: ['', '  ', :name, 'name', :bio]
      )

      expect(Undertow::Registry['Gadget'].dependencies.first[:watched_columns]).to eq(%w[name bio])
    end

    it 'stores nil when no watched-column filter is configured' do
      aggregate_failures do
        Gadget.undertow_depends_on(:author, foreign_key: :author_id)
        expect(Undertow::Registry['Gadget'].dependencies.first[:watched_columns]).to be_nil

        Gadget.undertow_depends_on(:author, foreign_key: :author_id, watched_columns: [])
        expect(Undertow::Registry['Gadget'].dependencies.first[:watched_columns]).to be_nil

        Gadget.undertow_depends_on(:author, foreign_key: :author_id, watched_columns: [''])
        expect(Undertow::Registry['Gadget'].dependencies.first[:watched_columns]).to be_nil
      end
    end
  end

  describe 'Trackable auto-inclusion' do
    it 'includes Trackable when undertow_sink is called' do
      Gadget.undertow_sink(:search_index) { |_m, _u, _d| }

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
      Gadget.undertow_sink(:search_index) { |_m, _u, _d| }
      Gadget.undertow_skip %w[title]
      Gadget.undertow_depends_on(:author, foreign_key: :author_id)

      count = Gadget.ancestors.count { |a| a == Undertow::Trackable }
      expect(count).to eq(1)
    end
  end

  describe '.undertow_sink' do
    it 'raises ArgumentError when no block is given' do
      expect {
        Gadget.undertow_sink(:search_index)
      }.to raise_error(ArgumentError, /requires a block/)
    end

    it 'stores the handler and max_batch_size on the config' do
      handler = ->(_m, _u, _d) {}
      Gadget.undertow_sink(:search_index, max_batch_size: 500, &handler)

      sink = Undertow::Registry['Gadget'].sinks[:search_index]
      expect(sink[:handler]).to eq(handler)
      expect(sink[:max_batch_size]).to eq(500)
    end

    it 'defaults max_batch_size to nil' do
      Gadget.undertow_sink(:search_index) { |_m, _u, _d| }

      expect(Undertow::Registry['Gadget'].sinks[:search_index][:max_batch_size]).to be_nil
    end

    it 'normalizes the sink name to a symbol' do
      Gadget.undertow_sink('search_index') { |_m, _u, _d| }

      expect(Undertow::Registry['Gadget'].sinks).to have_key(:search_index)
    end

    it 'overwrites a previously registered sink with the same name' do
      first  = ->(_m, _u, _d) {}
      second = ->(_m, _u, _d) {}
      Gadget.undertow_sink(:search_index, &first)
      Gadget.undertow_sink(:search_index, &second)

      expect(Undertow::Registry['Gadget'].sinks.size).to eq(1)
      expect(Undertow::Registry['Gadget'].sinks[:search_index][:handler]).to eq(second)
    end
  end

  describe '.undertow_skip' do
    it 'normalizes skip_columns to unique, non-blank strings' do
      Gadget.undertow_skip ['', '  ', :title, 'title', :description]

      expect(Undertow::Registry['Gadget'].skip_columns).to eq(%w[title description])
    end
  end
end
