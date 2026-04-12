# undertow

Buffered, dependency-aware change propagation for ActiveRecord models.

When a model changes, undertow pushes its ID into a Redis SET. A background job drains those IDs in batches and delivers them to a handler you define, typically a reindex or cache-bust job. Dependencies are declared on the model itself, so upstream changes (an author rename, a category destroy) automatically propagate to the affected root records.

## How it works

Models opt in via a small DSL. Undertow wires `after_commit` and `after_destroy` callbacks at boot, pushes dirty IDs to Redis, and delivers them in batches on each scheduler tick.

## Setup

```ruby
Undertow.configure do |c|
  c.redis          = Redis.new(url: ENV['REDIS_URL'])
  c.queue_name     = :undertow
  c.max_batch      = 1_000
  c.drain_lock_key = 'undertow:drain:lock'
end
```

Call `Undertow.tick` from your scheduler on each interval:

```ruby
every(1.second, 'undertow') { Undertow.tick }
```

## DSL

```ruby
class Activity < ApplicationRecord
  undertow_on_drain ->(model_name, ids, deleted_ids) {
    ActivityReindexJob.perform_later(ids, deleted_ids)
  }

  # columns that should not trigger propagation on their own
  undertow_skip %w[lock_version searchkick_reindexing]

  # FK dependency: reindex Activity when Provider changes
  undertow_depends_on :provider,
                      foreign_key:     :provider_id,
                      watched_columns: %w[approved mobile]

  # Resolver dependency: no FK on Activity, resolved through join table
  undertow_depends_on :location_series,
                      resolver:        ->(ls) { Activity.where(series_id: ls.series_id) },
                      watched_columns: %w[location_id hidden]
end
```

`undertow_depends_on` requires exactly one of `foreign_key:` or `resolver:`. `watched_columns:` is optional.. omit it to propagate on any change.

## DrainJob

`Undertow::DrainJob` uses the `queue_name` from your configuration. Set it in the configure block:

```ruby
Undertow.configure do |c|
  c.queue_name = :my_queue
end
```

The job releases the drain lock immediately on start so new work arriving mid-drain gets picked up on the next tick. If the batch is capped at `max_batch`, the model stays registered and drains again on the next tick. On any error, IDs are restored to Redis and the model is re-registered.

## Tests

```sh
bundle exec rspec
```
