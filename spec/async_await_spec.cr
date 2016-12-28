require "./spec_helper"

class AAWrap
  @@channel = AAChannel(Int32).new
  @@tcs = TaskCompletionSource(Int32).new

  def self.channel
    @@channel
  end

  def self.tcs
    @@tcs
  end
end

async def foo
  await AAWrap.channel.send(123)
  await AAWrap.channel.send(await AAWrap.channel.receive)
end

describe AsyncAwait do
  it "async/await work" do
    task = uninitialized Task(Nil)
    a = async_spawn {
      task = foo
    }
    AAWrap.channel.receive_with_csp.should eq(123)
    AAWrap.channel.send_with_csp(321)
    AAWrap.channel.receive_with_csp.should eq(321)
  end
end
