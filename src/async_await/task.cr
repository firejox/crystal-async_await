require "fiber"
require "atomic"
require "./awaitable"

module AsyncAwait
  module TaskInterface
    include Awaitable

    abstract def proc : Proc(Nil)?

    abstract def value_with_csp

    def wait
      wait { next }
    end

    def wait
      while status.incomplete?
        yield
      end
    end

    def wait_with_csp
      wait { Fiber.yield }
    end
  end

  class Task(T)
    include TaskInterface
    @value = uninitialized T
    @status : Status
    getter exception : Exception?
    getter proc : ->

    def initialize
      @proc = Proc(Void).new { }
      @status = Status::INCOMPLETE
    end

    def initialize(@value : T)
      @proc = Proc(Void).new { }
      @status = Status::COMPLETED
    end

    def value
      wait
      case @status
      when Status::COMPLETED
        return @value.as(T)
      when Status::FAULTED
        raise @exception.not_nil!
      else
        raise "Invalid Task Status"
      end
    end

    @[NoInline]
    def status
      @status
    end

    def value_with_csp
      wait_with_csp
      case @status
      when Status::COMPLETED
        return @value.as(T)
      when Status::FAULTED
        raise @exception.not_nil!
      else
        raise "Invalid Task Status"
      end
    end

    protected def value=(@value : T)
    end

    protected def status=(@status)
    end

    protected def exception=(@exception : Exception)
    end

    protected def proc=(@proc)
    end

    def self.from_exception(exception : Exception)
      task = new
      task.exception = exception
      task.status = Status::FAULTED
      task
    end

    def self.yield : Awaitable
      YieldAwaitable.new
    end

    class YieldAwaitable
      include Awaitable

      @status = Status::INCOMPLETE

      def value : Nil
      end

      def exception : Nil
      end

      @[NoInline]
      def status
        tmp, @status = @status, Status::COMPLETED
        tmp
      end
    end

    def self.delay(time : Time::Span) : TaskInterface
      TimedTask.new time
    end

    private class TimedTask
      include TaskInterface
      @status = Status::INCOMPLETE
      @cur_time = Time.now

      def initialize(@delay : Time::Span)
      end

      def value : Nil
        wait
      end

      def value_with_csp : Nil
        wait_with_csp
      end

      def exception : Nil
      end

      def proc : Nil
      end

      @[NoInline]
      def status
        if @delay.ticks != -1 && @delay.ago >= @cur_time
          @status = Status::COMPLETED
        end
        @status
      end
    end
  end
end

alias TaskInterface = AsyncAwait::TaskInterface
alias Task = AsyncAwait::Task
