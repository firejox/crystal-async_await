require "spec"
require "../src/async_await"

class AATest
  getter buffered_ch = AAChannel(Int32).new 32
  getter unbuffered_ch = AAChannel(Int32).new

  async def async_await_pings
    await @unbuffered_ch.send await @unbuffered_ch.receive
  end
end
