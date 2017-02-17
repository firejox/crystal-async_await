require "./spec_helper"

private async def foo
  st = Time.now
  await Task.delay(Time::Span.new(0, 0, 1))
  Time.now - st
end

private class Foo
  getter ch = AAChannel(String).new
  getter num : Int32?

  async def bar
    await Task.delay(Time::Span.new(0, 0, 1))
    await ch.receive
    await ch.send "Crystal!"
  end

  async def bar2
    @num = 123
    @num = await? Task(Int32).from_exception Exception.new
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

  it "work in main thread" do
    foo.value_with_csp.not_nil!.should be >= Time::Span.new(0, 0, 1)
  end

  it "await? fault task will be nil" do
    a = Foo.new
    a.bar2
    a.num.should be_nil
  end
end
