require "deque"
require "thread/mutex"
require "./task_completion_source"

module AsyncAwait
  class Channel(T)
    class ClosedError < ::Channel::ClosedError
    end

    def initialize(@capacity = 0)
      # queue store availiable data if status > 0, otherwise
      #  it store incomplete task need to be set data
      @queue = Deque(TaskCompletionSource(T)).new

      # min(the number of send task - recieve task, @capacity)
      @status = 0

      # store send task to send_wait if queue is full
      @send_wait = Deque(Tuple(T, TaskCompletionSource(T))).new

      # true if channel closed
      @closed = false

      # for synchronize
      @mutex = ::Thread::Mutex.new
    end

    def send(value : T)
      send_impl(value) { raise ClosedError.new }
    end

    def send?(value : T)
      send_impl(value) { break nil } || Task(Nil).new nil
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

    def send(value : T, wait_tcs : TaskCompletionSource(T))
      send_impl(value, wait_tcs) { raise ClosedError.new }
    end

    def send?(value : T, wait_tcs : TaskCompletionSource(T))
      send_impl(value, wait_tcs) { break nil } || Task(Nil).new nil
    end

    protected def send_impl(value : T, wait_tcs : TaskCompletionSource(T)) : Nil
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

    def receive
      receive_impl { raise ClosedError.new }
    end

    def receive?
      receive_impl { break nil } || Task(Nil).new nil
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

    def receive(tcs : TaskCompletionSource(T))
      receive_impl(tcs) { raise ClosedError.new }
    end

    def receive?(tcs : TaskCompletionSource(T))
      receive_impl(tcs) { break nil } || Task(Nil).new nil
    end

    protected def receive_impl(tcs : TaskCompletionSource(T)) : Nil
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

    def send_with_csp(value : T)
      send(value).value_with_csp
    end

    def send_with_csp?(value : T)
      send?(value).value_with_csp
    end

    def receive_with_csp : T
      receive.value_with_csp
    end

    def receive_with_csp? : T?
      receive?.value_with_csp
    end

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

    def self.receive_first(*channels : Channel(T)) forall T
      tcs = TaskCompletionSource(T).new
      channels.each &.receive(tcs)
      tcs.task
    end

    def self.receive_first(channels : Array(Channel(T))) forall T
      tcs = TaskCompletionSource(T).new
      channels.each &.receive(tcs)
      tcs.task
    end

    def self.receive_first_with_csp(*channels)
      receive_first(*channels).value_with_csp
    end

    def self.receive_first_with_csp(channels : Array)
      receive_first(channels).value_with_csp
    end

    def self.send_first(value : T, *channels : Channel(T)) forall T
      wait_tcs = TaskCompletionSource(T).new
      channels.each &.send(value, wait_tcs)
      wait_tcs.task
    end

    def self.send_first(value : T, channels : Array(Channel(T))) forall T
      wait_tcs = TaskCompletionSource(T).new
      channels.each &.send(value, wait_tcs)
      wait_tcs.task
    end

    def self.send_first_with_csp(value, *channels)
      send_first(value, *channels).value_with_csp
    end

    def self.send_first_with_csp(value, channels : Array)
      send_first(value, channels).value_with_csp
    end

    def self.select
      yield action = Selector.new
      action.task
    end

    def self.select_with_csp
      self.select do |action|
        yield action
      end.value_with_csp
    end

    private class SelectCompletionSource(T) < TaskCompletionSource(T)
      @proc : ->

      def initialize(@tcs : TaskCompletionSource(->), &block : T ->)
        super()
        @proc = ->{ block.call(@task.value) }
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

      def try_set_exception?(exception : Exception)
        if @tcs.try_set_exception? exception
          @task.exception = exception
          @task.status = AAStatus::FAULTED
          true
        else
          false
        end
      end

      protected def try_complete?
        @tcs.try_complete?
      end

      protected def reset : Nil
        @tcs.reset
      end

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

        def proc : Nil
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
