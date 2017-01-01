require "./spec_helper"

private async def foo
  st = Time.now
  await Task.delay(Time::Span.new(0, 0, 1))
  Time.now - st
end

describe AsyncAwait do
  it "async/await work" do
    task = uninitialized Task(Time::Span?)
    a = async_spawn {
      task = foo
    }
    a.join
    task.value.not_nil!.should be >= Time::Span.new(0, 0, 1)
  end
end
