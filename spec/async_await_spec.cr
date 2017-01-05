require "./spec_helper"

private async def foo
  st = Time.now
  await Task.delay(Time::Span.new(0, 0, 1))
  Time.now - st
end

private class Foo
  getter ch = AAChannel(String).new

  async def bar
    await Task.delay(Time::Span.new(0, 0, 1))
    await ch.receive
    await ch.send "Crystal!"
  end
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

  it "work with channels" do
    a = Foo.new

    async_spawn do
      a.bar
    end

    a.ch.send_with_csp "Hello"
    a.ch.receive_with_csp.should eq("Crystal!")
  end
end
