# :ocean: undertow

[![Gem Version](https://badge.fury.io/rb/undertow.svg?ts=2026050701)](https://badge.fury.io/rb/undertow)
[![CI](https://github.com/nallenscott/undertow/actions/workflows/ci.yml/badge.svg)](https://github.com/nallenscott/undertow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Rails apps often have models that represent a composition of data from multiple sources. A product listing might pull from categories, sellers, and inventory. A search document might aggregate fields from a dozen associations. A cache entry might depend on records several joins away. When any of those sources change, the composed record is stale and something downstream needs to react.

The usual approach is to add callbacks to the upstream models and fan out from there. That works for simple cases, but it gets messy fast. It's easy to miss associations, it creates hidden coupling between models that have no business knowing about each other, and it breaks down entirely when the relationship is indirect, through a join table or a scope.

Relational databases solve a version of this with materialized views: a precomputed result that tracks its own staleness and refreshes lazily when sources change. Undertow brings that pattern to ActiveRecord. Dependencies are declared on the root model, undertow resolves which records are affected when upstream data changes, and the affected IDs are buffered in a configurable store and delivered in batches to a handler you define, off the write path.

## Mental model

You don’t “update” derived state.

You declare how to rebuild it.. and let Undertow pull it back into consistency.

Like an undertow under the surface, it quietly keeps everything aligned.

## Requirements

- Ruby >= 3.0
- ActiveRecord ~> 7.0
- ActiveSupport ~> 7.0
- ActiveJob ~> 7.0

## Installation

Add Undertow to your Gemfile:

```ruby
gem "undertow"
```

If you want to use Redis or Valkey as the backing store, also add:

```ruby
gem "redis"
```

Then run:

```bash
bundle install
```

## Setup

Create `config/initializers/undertow.rb`:

```ruby
Undertow.configure do |c|
  c.store          = Undertow::Store::MemoryStore.new
  c.queue_name     = :undertow
  c.max_batch      = 1_000
  c.drain_lock_key = "undertow:drain:lock"
end
```

`MemoryStore` is the default, so setting `c.store` is optional unless you want a different backend.

`MemoryStore` keeps state in process memory and is intended for tests and single process development. Use `RedisStore` for multi process or multi dyno deployments.

For Redis or Valkey:

```ruby
Undertow.configure do |c|
  c.store = Undertow::Store::RedisStore.new(
    Redis.new(url: ENV["REDIS_URL"])
  )
end
```

`RedisStore` is compatible with Redis and Valkey servers that support standard Redis set and lock commands. It accepts a direct Redis client or a pooled client that responds to `with`.

| Option | Default | Description |
|---|---|---|
| `store` | `Undertow::Store::MemoryStore.new` | Store adapter implementation. |
| `queue_name` | `:undertow` | ActiveJob queue for `DrainJob`. |
| `max_batch` | `1_000` | Maximum IDs popped per model per drain. |
| `drain_lock_key` | `"undertow:drain:lock"` | Lock key used by the configured store. Set to `nil` to disable lock management. |

Call `Undertow.tick` from your scheduler on each interval:

```ruby
every(1.second, "undertow") { Undertow.tick }
```

## Root models

Undertow starts from the root model, the model that owns derived or aggregated state and needs to know when upstream data changes.

The root model defines:

- what it depends on  
- which columns matter  
- what to do when affected IDs are ready  

Upstream models need no configuration. Undertow wires their callbacks automatically at boot when a root model declares a dependency on them.

That’s the point.

The model that owns the derived state defines the contract.

## Defining dependencies

Here’s the whole shape:

```ruby
class Post < ApplicationRecord
  belongs_to :author
  has_many :post_tags
  has_many :tags, through: :post_tags

  undertow_skip %w[view_count updated_at]

  undertow_depends_on :author,
    foreign_key: :author_id,
    watched_columns: %w[name bio]

  undertow_depends_on :tag,
    resolver: ->(tag) {
      Post.joins(:post_tags).where(post_tags: { tag_id: tag.id })
    },
    watched_columns: %w[name slug]

  undertow_on_drain ->(model_name, ids, deleted_ids) {
    PostSyncJob.perform_later(ids, deleted_ids)
  }
end
```

Declare what affects the root model. Undertow figures out which root records are stale and delivers the IDs in batches.

Use `foreign_key:` when the root model directly references the upstream model:

```ruby
undertow_depends_on :author,
  foreign_key: :author_id,
  watched_columns: %w[name bio]
```

Use `resolver:` when there is no direct foreign key from the root model to the upstream model:

```ruby
undertow_depends_on :tag,
  resolver: ->(tag) {
    Post.joins(:post_tags).where(post_tags: { tag_id: tag.id })
  },
  watched_columns: %w[name slug]
```

Use `watched_columns:` when only certain upstream changes matter:

```ruby
undertow_depends_on :author,
  foreign_key: :author_id,
  watched_columns: %w[name bio]
```

## Skipping noisy columns

Use `undertow_skip` for columns on the root model that should not trigger downstream work.

```ruby
undertow_skip %w[view_count updated_at]
```

## Drain handler

Use `undertow_on_drain` to define what happens when a batch is ready.

```ruby
undertow_on_drain ->(model_name, ids, deleted_ids) {
  PostSyncJob.perform_later(ids, deleted_ids)
}
```

## Disabling tracking

```ruby
Undertow.without_tracking do
  Author.find_each { |author| author.update!(legacy: true) }
end
```

## Manually requeueing records

Use `undertow_requeue` to push records into the pending buffer without going through AR callbacks, useful for replaying a batch from a console or a data migration.

```ruby
Post.undertow_requeue                               # all records
Post.undertow_requeue(Post.where(author_id: 123))   # a relation
Post.undertow_requeue([136543, 136544])             # explicit ids
```

## DrainJob

`Undertow::DrainJob` is enqueued by `Undertow.tick` when pending work exists and the drain lock can be acquired.

- releases the lock immediately on start  
- drains in batches (`max_batch`)  
- restores IDs and emits an error event when the handler raises  
- continues draining on next tick if capped or after an error  

The drain lock has a default TTL of 30 seconds.

## Instrumentation

Undertow publishes `ActiveSupport::Notifications` events:

```ruby
ActiveSupport::Notifications.subscribe("drain.undertow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info(event.payload)
end
```

```ruby
ActiveSupport::Notifications.subscribe("error.undertow") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.error(event.payload)
end
```

## Upgrading

See [UPGRADING.md](UPGRADING.md) for version migration steps.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
