require "spec"
require "../src/async_await"

class Thread
  getter queue = Deque(TaskInterface).new

  def self.async_test(&block : ->)
    new {
      block.call
      while task = current.queue.shift?
        task.proc.try &.call
      end
    }
  end
end
