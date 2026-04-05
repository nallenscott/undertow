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
  create_table :authors, force: true do |t|
    t.string :name
    t.string :irrelevant  # watched by resolver dep
    t.string :bio         # genuinely unwatched — used to verify no push
  end

  create_table :posts, force: true do |t|
    t.string  :title
    t.integer :author_id
    t.string  :skipped       # undertow_skip covers this column
  end
end

# ---------------------------------------------------------------------------
# Extend AR::Base with the Undertow DSL (Railtie does this in a Rails app).
# ---------------------------------------------------------------------------
ActiveRecord::Base.extend(Undertow::DSL)

# ---------------------------------------------------------------------------
# Test models
# ---------------------------------------------------------------------------
class Author < ActiveRecord::Base; end

class Post < ActiveRecord::Base
  belongs_to :author

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

  # Resolver-based dep — :authors pluralised so _resolve_dep_class classifies it
  # to Author via "authors".classify => "Author"
  undertow_depends_on :authors,
                      resolver:        ->(a) { Post.where(author_id: a.id) },
                      watched_columns: %w[irrelevant]
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

    ActiveRecord::Base.connection.execute('DELETE FROM posts')
    ActiveRecord::Base.connection.execute('DELETE FROM authors')
  end
end
