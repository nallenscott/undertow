# frozen_string_literal: true

RSpec.describe Undertow::Trackable do
  describe 'callback registration' do
    before do
      Object.const_set(:Gadget, Class.new(ActiveRecord::Base) { self.table_name = 'posts' })
      Gadget.extend(Undertow::DSL)
      Gadget.undertow_on_drain ->(_m, _i, _d) {}
    end

    after do
      Object.send(:remove_const, :Gadget)
      Undertow::Registry.all.delete('Gadget')
    end

    it 'does not double-register callbacks when called multiple times' do
      config = Undertow::Registry['Gadget']
      Gadget.register_undertow_callbacks!(config)
      Gadget.register_undertow_callbacks!(config)

      push_count = 0
      allow(Undertow::Buffer).to receive(:push_pending).and_wrap_original do |original, *args|
        push_count += 1
        original.call(*args)
      end

      Gadget.create!(title: 'test')

      expect(push_count).to eq(1)
    end
  end

  describe 'self-tracking' do
    let!(:post) { Post.create!(title: 'test') }

    before { Undertow::Buffer.pop_pending('Post', 1_000) }

    describe 'on create' do
      it 'pushes unconditionally' do
        post.send(:_push_self_created)

        ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
        expect(ids).to include(post.id)
      end
    end

    describe 'on update' do
      it 'skips when saved_changes is empty' do
        allow(post).to receive(:saved_changes).and_return({})

        post.send(:_push_self_updated)

        expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
      end

      it 'skips when only ignored columns changed' do
        # Post's _undertow_ignored_columns includes 'skipped' via undertow_skip in spec_helper.
        allow(post).to receive(:saved_changes).and_return({ 'skipped' => [nil, 'x'] })

        post.send(:_push_self_updated)

        expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
      end

      it 'pushes when a tracked column changed' do
        allow(post).to receive(:saved_changes).and_return(
          { 'skipped' => [nil, 'x'], 'title' => %w[Old New] }
        )

        post.send(:_push_self_updated)

        ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
        expect(ids).to include(post.id)
      end
    end

    describe 'on restore' do
      it 'pushes unconditionally' do
        post.send(:_push_self_restored)

        ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
        expect(ids).to include(post.id)
      end
    end
  end

  describe 'dependency tracking' do
    let(:dep)     { { association: :author, foreign_key: :author_id, resolver: nil, watched_columns: %w[name] } }
    let!(:author) { Author.create!(name: 'Alice') }
    let!(:post)   { Post.create!(title: 'test', author: author) }

    before { Undertow::Buffer.pop_pending('Post', 1_000) }

    describe 'on update' do
      it 'pushes when a watched column changed' do
        allow(author).to receive(:saved_changes).and_return({ 'name' => ['Alice', 'Bob'] })

        Post._push_dep_updated(author, dep)

        ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
        expect(ids).to include(post.id)
      end

      it 'skips when no watched column changed' do
        allow(author).to receive(:saved_changes).and_return({ 'bio' => [nil, 'nobody'] })

        Post._push_dep_updated(author, dep)

        expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
      end

      it 'skips when saved_changes is empty' do
        allow(author).to receive(:saved_changes).and_return({})

        Post._push_dep_updated(author, dep)

        expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
      end

      it 'pushes unconditionally when no watched_columns are configured' do
        dep_no_watch = dep.merge(watched_columns: nil)
        allow(author).to receive(:saved_changes).and_return({ 'bio' => [nil, 'nobody'] })

        Post._push_dep_updated(author, dep_no_watch)

        ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
        expect(ids).to include(post.id)
      end
    end

    describe 'when no root records match' do
      it 'does not push' do
        unassociated_author = Author.create!(name: 'Bob')

        Post._push_dep_pending(unassociated_author, dep)

        expect(Undertow::Buffer.pop_pending('Post', 10)).to be_empty
      end
    end

    describe 'with a resolver dep' do
      it 'resolves IDs via the resolver lambda' do
        dep_with_resolver = dep.merge(
          resolver: ->(record) { Post.where(author_id: record.id) },
          foreign_key: nil,
          watched_columns: nil
        )

        Post._push_dep_pending(author, dep_with_resolver)

        ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
        expect(ids).to include(post.id)
      end
    end
  end

  describe '.undertow_requeue' do
    let!(:author)   { Author.create!(name: 'Alice') }
    let!(:post_one) { Post.create!(title: 'one', author: author) }
    let!(:post_two) { Post.create!(title: 'two', author: author) }

    before { Undertow::Buffer.pop_pending('Post', 1_000) }

    it 'defaults to :all and pushes every record id' do
      Post.undertow_requeue

      ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
      expect(ids).to match_array([post_one.id, post_two.id])
    end

    it 'accepts an ActiveRecord::Relation and pushes its ids' do
      Post.undertow_requeue(Post.where(id: post_one.id))

      ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
      expect(ids).to match_array([post_one.id])
    end

    it 'accepts an array of ids and pushes them as-is' do
      Post.undertow_requeue([post_two.id])

      ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
      expect(ids).to match_array([post_two.id])
    end

    it 'accepts a single bare id' do
      Post.undertow_requeue(post_one.id)

      ids = Undertow::Buffer.pop_pending('Post', 10).map(&:to_i)
      expect(ids).to match_array([post_one.id])
    end
  end
end
