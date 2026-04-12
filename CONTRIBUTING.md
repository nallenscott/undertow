# Contributing

## Reporting issues

Open an issue before submitting a PR for anything non-trivial. This keeps work from going in a direction that won't be merged.

## Making changes

```sh
bundle install
bundle exec rspec
```

All tests must pass. New behavior needs test coverage.

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/). This drives automated versioning and changelog generation.

- `fix:` — bug fix, produces a patch release
- `feat:` — new feature, produces a minor release
- `feat!:` / `fix!:` — breaking change, produces a major release
