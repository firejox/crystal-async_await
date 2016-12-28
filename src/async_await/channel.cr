require "deque"
require "thread/mutex"
require "./task_completion_source"

module AsyncAwait
  class Channel(T)
    def initialize(@capacity = 0)
      # queue store availiable data if status > 0, otherwise
      #  it store incomplete task need to be set data
      @queue = Deque(TaskCompletionSource(T)).new

      # min(the number of send task - recieve task, @capacity)
      @status = 0

      # store send task to send_wait if queue is full
      @send_wait = Deque(Tuple(TaskCompletionSource(T), TaskCompletionSource(Nil))).new

      # true if channel closed
      @closed = false

      # for synchronize
      @mutex = ::Thread::Mutex.new
    end

    def send(value : T)
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

            # make sure send task is incomplete
            if wait_tcs.try_set_value? nil
              @queue.push tcs
              @status += 1
            end
          else
            # make sure recieve task is complete
            if (tcs = @queue.first).try_complete?
              # make sure send task is complete
              if wait_tcs.try_set_value? nil
                tcs.complete_set_value value
                @queue.shift
                @status += 1
              else
                tcs.reset
              end
            else
              @queue.shift
              @status += 1
              next
            end
          end

          break
        end
      end
    end

    def receive
      @mutex.synchronize do |mtx|
        loop do
          if tuple = @send_wait.shift?
            # make sure send task is incomplete
            next unless tuple[1].try_set_value? nil

            @queue.push tuple[0]
            return @queue.shift.task
          elsif @status > 0
            @status -= 1
            return @queue.shift.task
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
          if tuple = @send_wait.first?
            # make sure recieve task is incomplete
            if tcs.try_complete?
              @send_wait.shift

              # make sure send task is incomplete
              if tuple[1].try_set_value? nil
                @queue.push tuple[0]
                ltcs = @queue.shift
                tcs.complete_set_value ltcs.task.value
              else
                tcs.reset
                next
              end
            end
          elsif @status > 0
            ltcs = @queue.first

            # make sure recieve task is not completed
            if tcs.try_set_value? ltcs.task.value
              @queue.shift
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
      send(value).wait_with_csp
    end

    def receive_with_csp : T
      receive.value_with_csp
    end

    def close
      return if @closed
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

    def closed?
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
      raise ::Channel::ClosedError.new if closed?
    end
  end
end

alias AAChannel = AsyncAwait::Channel
