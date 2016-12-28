require "./spec_helper"

class AAWrap
  @@channel = AAChannel(Time::Span).new
  @@tcs = TaskCompletionSource(Time::Span).new
  
  def self.channel
    @@channel
  end

  def self.tcs
    @@tcs
  end
end

async def foo
  stm = Time.now
  await Task.delay(Time::Span.new(0, 0, 1))
  etm = Time.now
  AAWrap.channel.send(etm - stm)
end

describe AsyncAwait do
  it "async/await work" do
    a = async_spawn {
      foo
    }
    AAWrap.channel.receive_with_csp.should be >= Time::Span.new(0, 0, 1)
  end
end
