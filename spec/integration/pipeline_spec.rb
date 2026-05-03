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

    it 'still pushes when both a skipped and a tracked column change together' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.update!(title: 'Changed', skipped: 'also changed')

      expect(pending_ids).to include(post.id)
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
  end

  describe 'dependency tracking' do
    let!(:category) { Category.create!(name: 'Tech') }
    let!(:author)   { Author.create!(name: 'Alice') }
    let!(:post)     { Post.create!(title: 'Hello', author: author) }

    before do
      PostCategory.create!(post: post, category: category)
      pending_ids # drain all create pushes
    end

    it 'pushes Post ID when a watched Author column changes' do
      author.update!(name: 'Bob')

      expect(pending_ids).to include(post.id)
    end

    it 'skips push when an unwatched Author column changes' do
      author.update!(bio: 'nobody')

      expect(pending_ids).to be_empty
    end

    it 'pushes Post ID when Author is destroyed' do
      author.destroy!

      expect(pending_ids).to include(post.id)
    end

    it 'pushes Post ID via resolver dep when its watched column changes' do
      category.update!(name: 'Science')

      expect(pending_ids).to include(post.id)
    end

    it 'skips resolver dep push when an unwatched column changes' do
      category.update!(slug: 'science')

      expect(pending_ids).to be_empty
    end

    it 'pushes Post ID via resolver dep when Category is destroyed' do
      category.destroy!

      expect(pending_ids).to include(post.id)
    end

    it 'pushes Post ID via FK dep when Author is restored' do
      author.run_callbacks(:restore)

      expect(pending_ids).to include(post.id)
    end

    it 'pushes all Post IDs when a category with multiple posts changes' do
      post2 = Post.create!(title: 'World', author: author)
      PostCategory.create!(post: post2, category: category)
      pending_ids # drain the create push for post2

      category.update!(name: 'Science')

      expect(pending_ids).to match_array([post.id, post2.id])
    end
  end

  describe 'restore tracking' do
    it 'pushes to the pending SET on restore, not the deleted SET' do
      post = Post.create!(title: 'Hello')
      pending_ids # drain create push

      post.run_callbacks(:restore)

      expect(pending_ids).to include(post.id)
      expect(deleted_ids).to be_empty
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
