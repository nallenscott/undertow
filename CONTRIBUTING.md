# Contributing

## Reporting issues

Open an issue before submitting a PR for anything non-trivial. This keeps work from going in a direction that won't be merged.

## Making changes

```sh
bundle install
bundle exec rspec
```

All tests must pass. New behavior needs test coverage.

### Backend adapter specs (Redis)

The default test run uses `MemoryStore` and skips backend adapter integration specs.

Run Redis adapter specs locally against a real backend:

```sh
docker run --rm -d --name undertow-redis -p 6379:6379 redis:7-alpine
RUN_REDIS_SPECS=1 bundle exec rspec spec/undertow/store/redis_store_spec.rb
docker stop undertow-redis
```

You can override the Redis connection URL with:

- `UNDERTOW_TEST_REDIS_URL` (default: `redis://127.0.0.1:6379/15`)

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/). This drives automated versioning and changelog generation.

- `fix:`, bug fix, produces a patch release
- `feat:`, new feature, produces a minor release
- `feat!:` / `fix!:`, breaking change, produces a major release
