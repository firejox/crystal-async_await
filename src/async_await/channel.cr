require "deque"
require "thread/mutex"
require "./task_completion_source"

module AsyncAwait
  class Channel(T)
    # Raised when send value to closed channel or receive value from empty closed channel
    class ClosedError < ::Channel::ClosedError
    end

    # Creates a new empty Channel with `capacity`
    #
    # The `capacity` is the size of buffer. If `capacity` is zero, then the channel is unbuffered;
    # Otherwise it is buffered channel.
    #
    # ```
    # unbuffered_channel = AAChannel(Int32).new
    # buffered_channel = AAChannel(Int32).new 5
    # ```
    def initialize(@capacity = 0)
      # queue store availiable data if status > 0, otherwise it
      # store incomplete task need to be set data
      @queue = Deque(TaskCompletionSource(T) | SelectCompletionSource(T)).new

      # min(the number of send task - recieve task, @capacity)
      @status = 0

      # store send task to send_wait if queue is full
      @send_wait = Deque(Tuple(T, TaskCompletionSource(T) | SelectCompletionSource(T))).new

      # true if channel closed
      @closed = false

      # for synchronize
      @mutex = ::Thread::Mutex.new
    end

    # Send value into channel. It returns `Task` for waiting send operation completed.
    # Raise `ClosedError` if closed.
    #
    # ```
    # channel = AAChannel(Int32).new 1
    # await channel.send 2 # => 2
    # ```
    def send(value : T)
      send_impl(value) { raise ClosedError.new }
    end

    # Send value into channel. It returns `Task` for waiting send operation completed.
    # Returns `nil` if closed.
    def send?(value : T)
      send_impl(value) { break nil }
    end

    protected def send_impl(value : T)
      @mutex.synchronize do |mtx|
        yield if @closed
        loop do
          if @status >= @capacity
            wait_tcs = TaskCompletionSource(T).new
            tuple = {value, wait_tcs}
            @send_wait.push tuple
            return wait_tcs.task
          elsif @status >= 0
            tcs = TaskCompletionSource(T).new
            tcs.value = value
            @queue.push tcs
            @status += 1
            return tcs.task
          else
            tcs = @queue.shift
            @status += 1

            # make sure receive task is incomplete
            next unless tcs.try_set_value? value
            return tcs.task
          end
        end
      end
    end

    # Send value into channel with given `TaskCompletionSource`. It allow to cancel send
    # by `TaskCompletionSource`. Raise `ClosedError` if closed.
    #
    # ```
    # ch = AAChannel(Int32).new 1
    # tcs = TaskCompletionSource(Int32).new
    # ch.send(1, tcs)
    # await tcs.task # => 1
    # ```
    def send(value : T, wait_tcs)
      send_impl(value, wait_tcs) do
        wait_tcs.try_set_exception? ClosedError.new
        raise ClosedError.new
      end
    end

    # Send value into channel with given `TaskCompletionSource`. It allow to cancel send
    # by `TaskCompletionSource`. Returns `nil` if closed.
    def send?(value : T, wait_tcs)
      send_impl(value, wait_tcs) do
        wait_tcs.try_set_exception? ClosedError.new
        break nil
      end
    end

    protected def send_impl(value : T, wait_tcs) : Nil
      @mutex.synchronize do |mtx|
        yield if @closed
        loop do
          if @status >= @capacity
            tuple = {value, wait_tcs}
            @send_wait.push tuple
          elsif @status >= 0
            # make sure send task is incomplete
            if wait_tcs.try_set_value? value
              @queue.push wait_tcs
              @status += 1
            end
          else
            # make sure recieve task is complete
            if (tcs = @queue.first).try_complete?
              # make sure send task is complete
              if wait_tcs.try_set_value? value
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

    # receive value from channel. It returns `Task` for waiting receive operation completed.
    # Raise `ClosedError` if closed.
    #
    # ```
    # ch = AAChannel(Int32).new
    # ch.send 1
    # await ch.receive # => 1
    # ```
    def receive
      receive_impl { raise ClosedError.new }
    end

    # Recieve value from channel. It returns `Task` for waiting receive operation completed.
    # Returns `nil` if closed.
    def receive?
      receive_impl { break nil }
    end

    protected def receive_impl
      @mutex.synchronize do |mtx|
        loop do
          if tuple = @send_wait.shift?
            # make sure send task is incomplete
            next unless tuple[1].try_set_value? tuple[0]
            @queue.push tuple[1]
            return @queue.shift.task
          elsif @status > 0
            @status -= 1
            return @queue.shift.task
          else
            yield if @closed
            tcs = TaskCompletionSource(T).new
            @queue.push tcs
            @status -= 1
            return tcs.task
          end
        end
      end
    end

    # Receive value from channel with `TaskCompletionSource`. It allow to cancel receive
    # by `TaskCompletionSource`. Raise `ClosedError` if closed.
    #
    # ```
    # ch = AAChannel(Int32).new
    # tcs = TaskCompletionSource(Int32).new
    # ch.send 1
    # ch.receive(tcs)
    # await tcs.task # => 1
    # ```
    def receive(tcs)
      receive_impl(tcs) do
        tcs.try_set_exception? ClosedError.new
        raise ClosedError.new
      end
    end

    # Receive value from channel with `TaskCompletionSource`. It allow to cancel receive
    # by `TaskCompletionSource`. Returns `nil` if closed.
    def receive?(tcs)
      receive_impl(tcs) do
        tcs.try_set_exception? ClosedError.new
        break nil
      end
    end

    protected def receive_impl(tcs) : Nil
      @mutex.synchronize do |mtx|
        loop do
          if tuple = @send_wait.first?
            # make sure recieve task is incomplete
            if tcs.try_complete?
              @send_wait.shift

              # make sure send task is incomplete
              if tuple[1].try_set_value? tuple[0]
                @queue.push tuple[1]
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
            yield if @closed
            @queue.push tcs
            @status -= 1
          end

          break
        end
      end
    end

    # Send value into channel and wait for completed by `TaskInterface#value_with_csp`.
    # Raise `ClosedError` if closed.
    #
    # ```
    # ch = AAChannel(Int32).new 1
    # ch.send_with_csp 2
    # ```
    def send_with_csp(value : T)
      send(value).value_with_csp
    end

    # Send value into channel and wait for completed by `TaskInterface#value_with_csp`.
    # Returns `nil` if closed.
    def send_with_csp?(value : T)
      send?(value).try &.value_with_csp
    end

    # Receive value from channel and wait for completed by `TaskInterface#value_with_csp`.
    # Raise `ClosedError` if closed.
    #
    # ```
    # ch = AAChannel(Int32).new
    # ch.send 1
    # ch.receive_with_csp # => 1
    # ```
    def receive_with_csp : T
      receive.value_with_csp
    end

    # Receive value from channel and wait for completed by `TaskInterface#value_with_csp`.
    # Returns `nil` if closed.
    def receive_with_csp? : T?
      receive?.try &.value_with_csp
    end

    # Close channel. It is able to receive value if there are remaining send values.
    #
    # ```
    # ch = AAChannel(Int32).new
    # ch.close
    # ```
    def close : Nil
      return if @closed
      @mutex.synchronize do |mtx|
        @closed = true
        if @status < 0
          @queue.each do |tcs|
            tcs.try_set_exception? ClosedError.new
          end
          @queue.clear
          @status = 0
        end
      end
    end

    # Returns `true` if channel closed, otherwise `false`.
    #
    # ```
    # ch = AAChannel(Int32).new
    # ch.closed? # => false
    # ch.close
    # ch.closed? # => true
    # ```
    def closed?
      @closed
    end

    # Returns `true` if the buffer of channel is full, otherwise `false`.
    #
    # ```
    # ch = AAChannel(Int32).new 1
    # ch.full? # => false
    # ch.send 1
    # ch.full? # => true
    # ```
    def full?
      if @capacity > 0
        @status >= @capacity
      else
        !@send_wait.empty?
      end
    end

    # Returns `true` if the buffer of channel is empty, otherwise `false`.
    #
    # ```
    # ch = AAChannel(Int32).new 1
    # ch.empty? # => true
    # ch.send 1
    # ch.empty? # => false
    # ```
    def empty?
      if @capacity > 0
        @status <= 0
      else
        @send_wait.empty?
      end
    end

    # Receive first value from given channels. It returns `Task` for waiting receive operation
    # completed.
    #
    # ```
    # ch1 = AAChannel(Int32).new
    # ch2 = AAChannel(Int32).new
    # ch1.send 1
    # await AAChannel.receive_first(ch1, ch2) # => 1
    # ```
    def self.receive_first(*channels : Channel(T)) forall T
      tcs = TaskCompletionSource(T).new
      channels.each &.receive?(tcs)
      tcs.task
    end

    # Receive first value from given channels. It returns `Task` for waiting receive operation
    # completed.
    def self.receive_first(channels : Array(Channel(T))) forall T
      tcs = TaskCompletionSource(T).new
      channels.each &.receive?(tcs)
      tcs.task
    end

    # Receive first value from given channels and wait for completed
    # by `TaskInterface#value_with_csp`
    #
    # ```
    # ch1 = AAChannel(Int32).new
    # ch2 = AAChannel(Int32).new
    # ch1.send 1
    # AAchannel.receive_first_with_csp(ch1, ch2) # => 1
    # ```
    def self.receive_first_with_csp(*channels)
      receive_first(*channels).value_with_csp
    end

    # Receive first value from given channels and wait for completed
    # by `TaskInterface#value_with_csp`
    def self.receive_first_with_csp(channels : Array)
      receive_first(channels).value_with_csp
    end

    # Send first value into given channels. It returns `Task` for waiting send operation
    # completed.
    #
    # ```
    # ch1 = AAChannel(Int32).new 1
    # ch2 = AAChannel(Int32).new 1
    # ch1.send 1
    # await AAChannel.send_first(2, ch1, ch2)
    # await ch2.receive # => 2
    # ```
    def self.send_first(value : T, *channels : Channel(T)) forall T
      wait_tcs = TaskCompletionSource(T).new
      channels.each &.send?(value, wait_tcs)
      wait_tcs.task
    end

    # Send first value into given channels. It returns `Task` for waiting send operation
    # completed.
    def self.send_first(value : T, channels : Array(Channel(T))) forall T
      wait_tcs = TaskCompletionSource(T).new
      channels.each &.send?(value, wait_tcs)
      wait_tcs.task
    end

    # Send first value into given channels and wait for completed by `TaskInterface#value_with_csp`
    #
    # ```
    # ch1 = AAChannel(Int32).new 1
    # ch2 = AAChannel(Int32).new 1
    # ch1.send 1
    # AAChannel.send_first_with_csp(2, ch1, ch2)
    # ch2.receive_with_csp # => 2
    # ```
    def self.send_first_with_csp(value, *channels)
      send_first(value, *channels).value_with_csp
    end

    # Send first value into given channels and wait for completed by `TaskInterface#value_with_csp`
    def self.send_first_with_csp(value, channels : Array)
      send_first(value, channels).value_with_csp
    end

    # Select one of action. It returns `Task` for waiting select operation
    # completed.
    #
    # ```
    # ch1 = AAChannel(Int32).new
    # ch2 = AAChannel(Int32).new
    # ch1.send 123
    # status = 0
    # await AAChannel.select do |x|
    #   x.add_receive_action ch1 do |val|
    #     val # => 123
    #     status = 1
    #   end
    #
    #   x.add_receive_action ch2 do |val|
    #     status = 2
    #   end
    # end
    # status # => 1
    # ```
    def self.select
      yield action = Selector.new
      action.task
    end

    # Select one of action and wait for completed by `TaskInterface#value_with_csp`.
    #
    # ```
    # ch1 = AAChannel(Int32).new
    # ch2 = AAChannel(Int32).new
    # ch1.send 123
    # status = 0
    # AAChannel.select_with_csp do |x|
    #   x.add_receive_action ch1 do |val|
    #     val # => 123
    #     status = 1
    #   end
    #
    #   x.add_receive_action ch2 do |val|
    #     status = 2
    #   end
    # end
    # status # => 1
    # ```
    def self.select_with_csp
      self.select do |action|
        yield action
      end.value_with_csp
    end

    private class SelectCompletionSource(T)
      @proc : ->
      getter task = Task(T).new

      def initialize(@tcs : TaskCompletionSource(->), &block : T ->)
        @proc = ->{ block.call(@task.value) }
      end

      def value=(value : T) : Nil
        unless try_set_value? value
          raise TaskCompletionSource::InvalidOperation.new
        end
      end

      def try_set_value?(value : T)
        if @tcs.try_set_value? @proc
          @task.value = value
          @task.status = AAStatus::COMPLETED
          true
        else
          false
        end
      end

      def exception=(exception : Exception) : Nil
        unless try_set_exception? exception
          raise TaskCompletionSource::InvalidOperation.new
        end
      end

      def try_set_exception?(exception : Exception)
        if @tcs.try_set_exception? exception
          @task.exception = exception
          @task.status = AAStatus::FAULTED
          true
        else
          false
        end
      end

      protected delegate try_complete?, reset, to: @tcs

      protected def complete_set_value(value : T) : Nil
        @tcs.complete_set_value @proc
        @task.value = value
        @task.status = AAStatus::COMPLETED
      end

      protected def complete_set_exception(exception : Exception) : Nil
        @tcs.complete_set_exception exception
        @task.exception = exception
        @task.status = AAStatus::FAULTED
      end
    end

    private class Selector
      @tcs = TaskCompletionSource(->).new

      def add_send_action(ch : Channel(T), value : T, &block : T ->) forall T
        scs = SelectCompletionSource(T).new @tcs, &block
        ch.send(value, scs)
      end

      def add_receive_action(ch : Channel(T), &block : T ->) forall T
        scs = SelectCompletionSource(T).new @tcs, &block
        ch.receive scs
      end

      protected def task
        SelectedTask.new @tcs.task
      end

      class SelectedTask
        include TaskInterface
        @status = Status::INCOMPLETE
        @exception : Exception?

        def initialize(@task : Task(->))
        end

        def value : Nil
          wait
          if @status.completed?
            nil
          else
            raise @exception.not_nil!
          end
        end

        def value_with_csp
          wait_with_csp
          if @status.completed?
            nil
          else
            raise @exception.not_nil!
          end
        end

        def exception
          @exception
        end

        def status
          return @status unless @status.incomplete?
          return Status::INCOMPLETE if @task.status.incomplete?

          if @task.status.completed?
            begin
              @task.value.call
              @status = Status::COMPLETED
            rescue ex
              @exception = ex
              @status = Status::FAULTED
            end
          else
            @exception = @task.exception
            @status = @task.status
          end

          @status
        end
      end
    end
  end
end

alias AAChannel = AsyncAwait::Channel
