# frozen_string_literal: true

RSpec.describe Undertow::Trackable do
  # Use Gadget as an isolated model class — avoids touching Post's already-wired
  # callbacks and gives us a clean @_undertow_callbacks_registered flag each time.
  before do
    Object.const_set(:Gadget, Class.new(ActiveRecord::Base) { self.table_name = 'posts' })
    Gadget.extend(Undertow::DSL)
    Gadget.undertow_on_drain ->(_m, _i, _d) {}
  end

  after do
    Object.send(:remove_const, :Gadget)
    Undertow::Registry.all.delete('Gadget')
  end

  describe '.register_undertow_callbacks!' do
    it 'is idempotent — calling twice does not double-fire callbacks' do
      config = Undertow::Registry['Gadget']
      Gadget.register_undertow_callbacks!(config)  # first call
      Gadget.register_undertow_callbacks!(config)  # second — must be a no-op

      push_count = 0
      allow(Undertow::Buffer).to receive(:push_pending).and_wrap_original do |original, *args|
        push_count += 1
        original.call(*args)
      end

      Gadget.create!(title: 'test')

      expect(push_count).to eq(1)
    end
  end

  describe '#_push_self_pending (skip_columns guard)' do
    let!(:post) { Post.create!(title: 'test') }

    before { Undertow::Buffer.pop_pending('Post', 1_000) } # discard the create push

    it 'fires when saved_changes is empty regardless of the ignore list' do
      # after_destroy / update_columns leave saved_changes == {} — must always push
      allow(post).to receive(:saved_changes).and_return({})

      post.send(:_push_self_pending)

      ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
      expect(ids).to include(post.id)
    end

    it 'suppresses push when every changed key is in skip_columns' do
      allow(post).to receive(:saved_changes).and_return({ 'skipped' => [nil, 'x'] })

      post.send(:_push_self_pending)

      ids = Undertow::Buffer.pop_pending('Post', 10)
      expect(ids).to be_empty
    end

    it 'fires when a non-ignored column is also present in saved_changes' do
      allow(post).to receive(:saved_changes).and_return(
        { 'skipped' => [nil, 'x'], 'title' => %w[Old New] }
      )

      post.send(:_push_self_pending)

      ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
      expect(ids).to include(post.id)
    end
  end
end
