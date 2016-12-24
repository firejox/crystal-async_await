require "deque"
require "thread/mutex"
require "./task_completion_source"

module AsyncAwait
  class ChannelClosedError < Exception
    def initialize(mag = "Channel is closed")
      super(msg)
    end
  end

  module Channel(T)
    def self.new(capacity) : Channel(T)
      BufferedChannel(T).new capacity
    end

    def self.new : Channel(T)
      BufferedChannel(T).new 0
    end

    abstract def send(value : T) : TaskInterface
    abstract def receive : TaskInterface

    abstract def send_with_csp(value : T)
    abstract def receive_with_csp : T

    abstract def close
    abstract def closed?

    abstract def full?
    abstract def empty?

    private def raise_if_closed
      raise ChannelClosedError.new if closed?
    end
  end

  class BufferedChannel(T)
    include Channel(T)

    def initialze(@capacity = 32)
      @queue = Deque(TaskCompletionSource(T)).new
      @status = 0
      @send_wait = Deque(Tuple(TaskCompletionSource(T), TaskCompletionSource(Nil))).new
      @closed = false
      @mutex = Thread::Mutex.new
    end

    def send(value : T) : TaskInterface
      @mutex.synchronize do |mtx|
        raise_if_closed
        loop do
          if @status >= @capacity
            tcs = TaskCompletionSource(T).new
            tcs.value = value
            wait_tcs = TaskCompletionSource(Nil).new
            tuple = {tcs, wait_tcs}
            @send_wait.push tuple
            return wait_tcs.task
          elsif @status >= 0
            tcs = TaskCompletionSource(T).new
            tcs.value = value
            @queue.push tcs.task
            @status += 1
            return Task(Nil).new nil
          else
            tcs = @queue.shift
            @status += 1
            next unless tcs.try_set_value? value
            return Task(Nil).new nil
          end
        end
      end
    end

    def send(value : T, wait_tcs : TaskCompletionSource(Nil))
      @mutex.synchronize do |mtx|
        raise_if_closed
        loop do
          if @status >= @capacity
            tcs = TaskCompletionSource(T).new
            tcs.value = value
            tuple = {tcs, wait_tcs}
            @send_wait.push tuple
          elsif @status >= 0
            tcs = TaskCompletionSource(T).new
            tcs.value = value
            if wait_tcs.try_set_value? nil
              @queue.push tcs.task
              @status += 1
            end
          else
            if wait_tcs.try_complete?
              tcs = @queue.shift
              @status += 1
              if tcs.try_set_value? value
                wait_tcs.complete_set_value nil
              else
                wait_tcs.reset
                next
              end
            end
          end

          break
        end
      end
    end

    def receive : TaskInterface
      @mutex.synchronize do |mtx|
        raise_if_closed

        loop do
          if tuple = @send_wait.shift?
            next unless tuple[1].try_set_value? nil
            @queue.push tuple[0]
            tcs = @queue.shift
            return tcs.task
          elsif @status > 0
            tcs = @queue.shift
            @status -= 1
            return tcs.task
          else
            tcs = TaskCompletionSource(T).new
            @queue.push tcs
            @status -= 1
            return tcs.task
          end
        end
      end
    end

    def recieve(tcs : TaskCompletionSource(T))
      @mutex.synchronize do |mtx|
        raise_if_closed

        loop do
          if tuple = @send_wait.shift?
            next unless tuple[1].try_set_value? nil
            @queue.push tuple[0]
            ltcs = @queue.shift
            unless tcs.try_set_value? ltcs.task.value
              @queue.unshift ltcs
            end
          elsif @status > 0
            ltcs = @queue.shift
            unless tcs.try_set_value? ltcs.task.value
              @queue.unshift ltcs
            else
              @status -= 1
            end
          else
            @queue.push tcs
            @status -= 1
          end

          break
        end
      end
    end

    def send_with_csp(value : T)
      task = send value
      task.wait_with_csp
    end

    def recieve_with_csp : T
      task = recieve
      task.value_with_csp
    end

    def close
      @mutex.synchronize do |mtx|
        @closed = true
        if @status < 0
          @queue.each do |tcs|
            tcs.try_set_exception? ChannelClosedError.new
          end
        end
        @send_wait.each do |tuple|
          tuple[1].try_set_exception? ChannelClosedError.new
        end
        @queue.clear
        @send_wait.clear
        @status = 0
      end
    end

    def close?
      @close
    end

    def full?
      if @capacity > 0
        @status >= @capacity
      else
        !@send_wait.empty?
      end
    end

    def empty?
      if @capacity > 0
        @status <= 0
      else
        @send_wait.empty?
      end
    end
  end
end
