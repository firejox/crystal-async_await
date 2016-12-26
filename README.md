# async_await [![Build Status](https://travis-ci.org/firejox/async_await.svg)](https://travis-ci.org/firejox/async_await)

async/await for Crystal

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  async_await:
    github: firejox/crystal-async_await
```

## Usage

```crystal
require "async_await"

async def foo
  await Task.delay(Time::Span.new(0, 0, 1))
end
```

another way for concurrent

# Roadmap
- [ ] Async IO
- [ ] Thread Pool Support
- [ ] Cancellation for Task
- [ ] Test more

## Contributing

1. Fork it ( https://github.com/firejox/crystal-async_await/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [firejox](https://github.com/firejox) firejox - creator, maintainer
