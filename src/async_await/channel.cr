require "deque"
require "thread/mutex"
require "./task_completion_source"

module AsyncAwait
  class Channel(T)
    def initialize(@capacity = 0)
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
            @queue.push tcs
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

    def send(value : T, wait_tcs : TaskCompletionSource(Nil)) : Nil
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
              @queue.push tcs
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
            raise_if_closed
            tcs = TaskCompletionSource(T).new
            @queue.push tcs
            @status -= 1
            return tcs.task
          end
        end
      end
    end

    def receive(tcs : TaskCompletionSource(T)) : Nil
      @mutex.synchronize do |mtx|
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
            raise_if_closed
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

    def receive_with_csp : T
      task = receive
      task.value_with_csp
    end

    def close
      @mutex.synchronize do |mtx|
        @closed = true
        if @status < 0
          @queue.each do |tcs|
            tcs.try_set_exception? ::Channel::ClosedError.new
          end
          @queue.clear
          @status = 0
        end
      end
    end

    def close?
      @closed
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

    private def raise_if_closed
      raise ::Channel::ClosedError.new if close?
    end
  end
end

alias AAChannel = AsyncAwait::Channel
