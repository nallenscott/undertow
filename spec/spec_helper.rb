# frozen_string_literal: true

require 'active_record'
require 'active_job'
require 'redis'
require 'mock_redis'
require 'undertow'

# ---------------------------------------------------------------------------
# ActiveJob
# ---------------------------------------------------------------------------
ActiveJob::Base.queue_adapter = :test

# ---------------------------------------------------------------------------
# In-memory SQLite database
# Two simple models: Author (dependency) and Post (root tracked model).
# No timestamps — keeps saved_changes clean so skip_columns tests are precise.
# ---------------------------------------------------------------------------
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

ActiveRecord::Schema.define do
  create_table :categories, force: true do |t|
    t.string :name
    t.string :slug         # genuinely unwatched — used to verify no push
  end

  create_table :authors, force: true do |t|
    t.string :name
    t.string :bio          # genuinely unwatched — used to verify no push
  end

  create_table :posts, force: true do |t|
    t.string  :title
    t.integer :author_id
    t.string  :skipped       # undertow_skip covers this column
  end

  create_table :post_categories, force: true do |t|
    t.integer :post_id
    t.integer :category_id
  end
end

# ---------------------------------------------------------------------------
# Extend AR::Base with the Undertow DSL (Railtie does this in a Rails app).
# ---------------------------------------------------------------------------
ActiveRecord::Base.extend(Undertow::DSL)

# ---------------------------------------------------------------------------
# Test models
# ---------------------------------------------------------------------------
class Category < ActiveRecord::Base
  has_many :post_categories
  has_many :posts, through: :post_categories
end

class PostCategory < ActiveRecord::Base
  belongs_to :post
  belongs_to :category
end

class Author < ActiveRecord::Base
  define_model_callbacks :restore
end

class Post < ActiveRecord::Base
  belongs_to :author
  has_many :post_categories
  has_many :categories, through: :post_categories

  # Enables after_restore callback wiring in register_undertow_callbacks!
  define_model_callbacks :restore

  # Captured drain calls — cleared in before(:each).
  DRAINED = []

  undertow_on_drain ->(model_name, ids, deleted_ids) {
    Post::DRAINED << {
      model_name:  model_name,
      ids:         ids.map(&:to_i),
      deleted_ids: deleted_ids.map(&:to_i)
    }
  }

  undertow_skip %w[skipped]

  undertow_depends_on :author,
                      foreign_key:     :author_id,
                      watched_columns: %w[name]

  # Resolver dep — Post has no FK on Category; resolved through join table.
  undertow_depends_on :category,
                      resolver:        ->(c) { c.posts },
                      watched_columns: %w[name]
end

# ---------------------------------------------------------------------------
# Wire after_commit callbacks (Railtie does this via config.to_prepare).
# ---------------------------------------------------------------------------
Undertow::Registry.all.each do |model_name, config|
  model_name.constantize.register_undertow_callbacks!(config)
end

# ---------------------------------------------------------------------------
# Per-test reset: fresh Redis, empty DB tables, empty drain capture.
# ---------------------------------------------------------------------------
RSpec.configure do |config|
  config.before(:each) do
    Undertow.instance_variable_set(:@configuration, nil)
    Undertow.configure { |c| c.redis = MockRedis.new }

    Post::DRAINED.clear

    ActiveRecord::Base.connection.execute('DELETE FROM post_categories')
    ActiveRecord::Base.connection.execute('DELETE FROM posts')
    ActiveRecord::Base.connection.execute('DELETE FROM authors')
    ActiveRecord::Base.connection.execute('DELETE FROM categories')
  end
end
