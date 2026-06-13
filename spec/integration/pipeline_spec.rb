# frozen_string_literal: true

RSpec.describe 'Undertow pipeline', type: :integration do
  def pending_ids
    Undertow::Buffer.pop_pending('Post', 1_000).map(&:to_i)
  end

  def deleted_ids
    Undertow::Buffer.pop_deleted('Post', 1_000).map(&:to_i)
  end

  describe 'self-tracking' do
    it 'pushes the ID to pending on create' do
      post = Post.create!(title: 'Hello')

      expect(pending_ids).to include(post.id)
    end

    it 'pushes the ID to pending on update of a tracked column' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.update!(title: 'World')

      expect(pending_ids).to include(post.id)
    end

    it 'skips push when only skip_columns changed' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.update!(skipped: 'ignored')

      expect(pending_ids).to be_empty
    end

    it 'pushes the ID to deleted on destroy' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.destroy!

      expect(deleted_ids).to include(post.id)
    end

    it 'skips push inside without_tracking' do
      Undertow.without_tracking { Post.create!(title: 'Suppressed') }

      expect(pending_ids).to be_empty
    end

    it 'does not push on a no-op save' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.save!

      expect(pending_ids).to be_empty
    end

    it 'pushes to the pending SET on restore, not the deleted SET' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.run_callbacks(:restore)

      expect(pending_ids).to include(post.id)
      expect(deleted_ids).to be_empty
    end
  end

  describe 'dependency tracking' do
    let!(:category) { Category.create!(name: 'Tech') }
    let!(:author)   { Author.create!(name: 'Alice') }
    let!(:post)     { Post.create!(title: 'Hello', author: author) }

    before do
      PostCategory.create!(post: post, category: category)
      pending_ids # drain all create pushes
    end

    describe 'on update' do
      it 'pushes Post IDs when a watched FK dep column changes' do
        author.update!(name: 'Bob')

        expect(pending_ids).to include(post.id)
      end

      it 'skips push when an unwatched FK dep column changes' do
        author.update!(bio: 'nobody')

        expect(pending_ids).to be_empty
      end

      it 'does not push on a no-op save of a dep' do
        author.save!

        expect(pending_ids).to be_empty
      end

      it 'pushes Post IDs when a watched resolver dep column changes' do
        category.update!(name: 'Science')

        expect(pending_ids).to include(post.id)
      end

      it 'skips push when an unwatched resolver dep column changes' do
        category.update!(slug: 'science')

        expect(pending_ids).to be_empty
      end

      it 'pushes all associated Post IDs' do
        post2 = Post.create!(title: 'World', author: author)
        PostCategory.create!(post: post2, category: category)
        pending_ids # drain create push for post2

        category.update!(name: 'Science')

        expect(pending_ids).to match_array([post.id, post2.id])
      end
    end

    describe 'on destroy' do
      it 'pushes Post IDs for a FK dep' do
        author.destroy!

        expect(pending_ids).to include(post.id)
      end

      it 'pushes Post IDs for a resolver dep' do
        category.destroy!

        expect(pending_ids).to include(post.id)
      end
    end

    describe 'on restore' do
      it 'pushes Post IDs for a FK dep' do
        author.run_callbacks(:restore)

        expect(pending_ids).to include(post.id)
      end
    end

    describe 'on create' do
      it 'pushes Post IDs regardless of watched_columns' do
        # Create the post first (SQLite enforces no FK constraints), then create
        # the author so the dep callback fires against the pre-existing post.
        next_author_id = (Author.maximum(:id) || 0) + 1
        owned_post = Post.create!(title: 'Hello', author_id: next_author_id)
        pending_ids # drain self-tracking create push

        Author.create!(id: next_author_id, bio: 'nobody') # name (watched) stays nil

        expect(pending_ids).to include(owned_post.id)
      end
    end
  end

  describe 'full drain' do
    it 'calls on_drain with correct pending IDs and clears the buffer' do
      post1 = Post.create!(title: 'A')
      post2 = Post.create!(title: 'B')

      Undertow::DrainJob.new.perform

      expect(Post::DRAINED.length).to eq(1)
      result = Post::DRAINED.first
      expect(result[:model_name]).to eq('Post')
      expect(result[:ids]).to match_array([post1.id, post2.id])
      expect(result[:deleted_ids]).to be_empty
      expect(Undertow::Buffer.pending?).to be false
    end

    it 'includes deleted IDs in the on_drain call' do
      post = Post.create!(title: 'Gone')
      pending_ids # drain create push
      post.destroy!

      Undertow::DrainJob.new.perform

      result = Post::DRAINED.first
      expect(result[:ids]).to be_empty
      expect(result[:deleted_ids]).to include(post.id)
    end

    it 'leaves remainder in buffer when capped at max_batch' do
      Undertow.configuration.max_batch = 2
      3.times { |i| Post.create!(title: "Post #{i}") }

      Undertow::DrainJob.new.perform

      expect(Undertow::Buffer.remaining('Post')).to eq(1)
      expect(Undertow::Buffer.pending?).to be true
    end
  end
end
