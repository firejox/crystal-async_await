require "./spec_helper"

async def foo
  await Task.delay(Time::Span.new(0, 0, 1))
end

describe AsyncAwait do
  it "async/await work" do
    a = Thread.async_test {
      foo
    }
    start_time = Time.now
    a.join
    end_time = Time.now
    (end_time - start_time).should be >= Time::Span.new(0, 0, 1)
  end
end
