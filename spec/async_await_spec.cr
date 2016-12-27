require "./spec_helper"

async def foo
  stm = Time.now
  await Task.delay(Time::Span.new(0, 0, 1))
  etm = Time.now
  etm - stm
end

describe AsyncAwait do
  it "async/await work" do
    time_diff = uninitialized Task(Time::Span?)
    async_spawn {
      time_diff = foo
    }
    time_diff.value.as(Time::Span).should be >= Time::Span.new(0, 0, 1)
  end
end
