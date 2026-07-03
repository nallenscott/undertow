# Upgrading Undertow

## Table of contents

- [0.4.x to 0.5.x](#04x-to-05x)
- [0.3.x to 0.4.x](#03x-to-04x)
- [0.1.x to 0.2.x](#01x-to-02x)

## 0.4.x to 0.5.x

### 1) Replace `undertow_on_drain` with `undertow_sink`

`undertow_on_drain` is removed. Models now declare one or more named sinks via `undertow_sink`, each receiving the same `(model_name, upserted_ids, deleted_ids)` on every drain.

Before:

```ruby
undertow_on_drain ->(model_name, upserted_ids, deleted_ids) {
  PostSyncJob.perform_later(upserted_ids, deleted_ids)
}
```

After:

```ruby
undertow_sink(:post_sync) { |model_name, upserted_ids, deleted_ids|
  PostSyncJob.perform_later(upserted_ids, deleted_ids)
}
```

If you had a single `undertow_on_drain` handler, this is a mechanical rename, pick any sink name you like. If you need a second sink (e.g. a search index and a Kafka topic), add a second `undertow_sink` call; optionally set `max_batch_size:` on a sink whose downstream call has a tighter limit than the others.

`drain.undertow`'s payload gains a `sink:` key, and now publishes once per sink (per chunk, if that sink's `max_batch_size` is smaller than the popped batch) rather than once per model. `error.undertow`'s payload also gains `sink:`, identifying which sink raised; the whole batch is still restored and retried on the next tick regardless of which sink failed.

## 0.3.x to 0.4.x

### 1) Rename `ids` to `upserted_ids`

The `undertow_on_drain` handler's second positional argument, and the `drain.undertow` notification payload key, are renamed from `ids` to `upserted_ids` to read unambiguously alongside `deleted_ids`.

Before:

```ruby
undertow_on_drain ->(model_name, ids, deleted_ids) {
  PostSyncJob.perform_later(ids, deleted_ids)
}
```

After:

```ruby
undertow_on_drain ->(model_name, upserted_ids, deleted_ids) {
  PostSyncJob.perform_later(upserted_ids, deleted_ids)
}
```

If you subscribe to `drain.undertow` directly, update `event.payload[:ids]` to `event.payload[:upserted_ids]`.

## 0.1.x to 0.2.x

### 1) Update initializer configuration

Before:

```ruby
Undertow.configure do |c|
  c.redis = Redis.new(url: ENV['REDIS_URL'])
end
```

After:

```ruby
Undertow.configure do |c|
  c.store = Undertow::Store::RedisStore.new(Redis.new(url: ENV['REDIS_URL']))
end
```

### 2) Add `redis` explicitly if you use `RedisStore`

`redis` is no longer a runtime dependency of `undertow`, so applications using `RedisStore` should add:

```ruby
gem 'redis'
```

### 3) Be explicit in production

`0.2.x` defaults to `MemoryStore`. If you rely on distributed buffering and locking, configure `RedisStore` explicitly in your production initializer.

### 4) Custom store adapters

If you implemented a custom store adapter, rename interface methods:

- `set_add` -> `add_members`
- `set_remove` -> `remove_member`
- `set_members` -> `members`
- `set_pop` -> `pop_members`
- `set_size` -> `member_count`
