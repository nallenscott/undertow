# Upgrading Undertow

## Table of contents

- [0.1.x to 0.2.x](#01x-to-02x)

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
