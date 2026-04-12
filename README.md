# undertow

[![CI](https://github.com/nallenscott/undertow/actions/workflows/ci.yml/badge.svg)](https://github.com/nallenscott/undertow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Rails apps often have models that represent a composition of data from multiple sources. A product listing might pull from categories, sellers, and inventory. A search document might aggregate fields from a dozen associations. A cache entry might depend on records several joins away. When any of those sources change, the composed record is stale and something downstream needs to react.

The usual approach is to add callbacks to the upstream models and fan out from there. That works for simple cases, but it gets messy fast. It's easy to miss associations, it creates hidden coupling between models that have no business knowing about each other, and it breaks down entirely when the relationship is indirect, through a join table or a scope.

Relational databases solve a version of this with materialized views: a precomputed result that tracks its own staleness and refreshes lazily when sources change. Undertow brings that pattern to ActiveRecord. Dependencies are declared on the root model, undertow resolves which records are affected when upstream data changes, and the affected IDs are buffered in Redis and delivered in batches to a handler you define, off the write path.

## Requirements

- Ruby >= 3.0
- Rails 7.0+
- Redis 4.0+
- ActiveJob

## Installation

```ruby
gem 'undertow'
```

## Setup

Create `config/initializers/undertow.rb`:

```ruby
Undertow.configure do |c|
  c.redis          = Redis.new(url: ENV['REDIS_URL'])
  c.queue_name     = :undertow
  c.max_batch      = 1_000
  c.drain_lock_key = 'undertow:drain:lock'
end
```

| Option | Default | Description |
|---|---|---|
| `redis` | none | A `Redis` client or connection pool. Required. |
| `queue_name` | `:undertow` | ActiveJob queue for `DrainJob`. |
| `max_batch` | `1_000` | Maximum IDs popped per model per drain. |
| `drain_lock_key` | `'undertow:drain:lock'` | Redis key for the distributed drain lock. Set to `nil` to disable lock management. |

Call `Undertow.tick` from your scheduler on each interval:

```ruby
every(1.second, 'undertow') { Undertow.tick }
```

## Root models

The DSL is declared on the **root model**, the model that owns derived or aggregated state and needs to know when upstream data changes. The root model defines what it depends on, which columns matter, and what to do when affected IDs are ready.

Upstream models need no configuration. Undertow wires their callbacks automatically at boot when a root model declares a dependency on them.

## DSL

The following examples assume `Post` is the root model, with `Author` as a FK dependency and `Tag` as a resolver dependency through a `post_tags` join table.

### `undertow_on_drain(callable)`

Registers the handler invoked when a batch of IDs is ready. The callable receives:

- `model_name`, string name of the root model
- `ids`, array of IDs that were updated
- `deleted_ids`, array of IDs that were destroyed

```ruby
undertow_on_drain ->(model_name, ids, deleted_ids) {
  PostSyncJob.perform_later(ids, deleted_ids)
}
```

### `undertow_skip(columns)`

An array of column names on the root model that should not trigger propagation when they change. Use this for columns that update frequently but don't affect downstream state.

```ruby
undertow_skip %w[view_count updated_at]
```

### `undertow_depends_on(association, foreign_key:, watched_columns:)`
### `undertow_depends_on(association, resolver:, watched_columns:)`

Declares a dependency on an upstream model. Requires exactly one of:

- `foreign_key:`, the column on the root model that holds the upstream ID. Undertow uses it to find affected root records directly.
- `resolver:`, a lambda that receives the changed upstream record and returns the affected root records. Use this when there is no direct FK (e.g. a join table).

`watched_columns:` is an optional array of column names on the **upstream** model. When provided, propagation only fires when one of those columns changes. Omit it to propagate on any change to the upstream model.

```ruby
# FK dependency: Post has an author_id column
undertow_depends_on :author,
                    foreign_key:     :author_id,
                    watched_columns: %w[name bio]

# Resolver dependency: no FK on Post, association is through a join table
undertow_depends_on :tag,
                    resolver:        ->(tag) { Post.joins(:post_tags).where(post_tags: { tag_id: tag.id }) },
                    watched_columns: %w[name slug]
```

## Disabling tracking

`Undertow.without_tracking` suppresses all buffer pushes inside the block. Useful in tests, seeds, and data migrations where dependency callbacks should not fire.

```ruby
Undertow.without_tracking do
  Author.find_each { |a| a.update!(legacy: true) }
end
```

Tracking state is thread-local and restored when the block exits, even if it raises.

## DrainJob

`Undertow::DrainJob` is enqueued by `Undertow.tick` when pending work exists and the drain lock can be acquired. It runs on the queue set in your configuration.

The job releases the drain lock immediately on start, so the scheduler can enqueue a new job for IDs arriving mid-drain without waiting. If a batch is capped at `max_batch`, the model stays registered and drains again on the next tick. On any error, IDs are restored to Redis and the model is re-registered.

The drain lock has a default TTL of 30 seconds as a safety valve in case the job process dies before releasing it.

## Instrumentation

Undertow publishes `ActiveSupport::Notifications` events:

- `drain.undertow`, fired after each successful drain. Payload: `model`, `ids`, `deleted_ids`
- `error.undertow`, fired when a drain fails. Payload: `model`, `exception`

## License

MIT. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
