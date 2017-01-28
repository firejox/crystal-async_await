require "thread"

module AsyncAwait
  class ThreadPool
    @@threads = Array(AAThread).new(8) do
      AAThread.new false { }
    end
    @@channels : Array(AAChannel(->)) = @@threads.map &.channel

    def self.queue(proc)
      AAChannel.send_first(proc, @@channels)
    end
  end
end

alias AAThreadPool = AsyncAwait::ThreadPool
