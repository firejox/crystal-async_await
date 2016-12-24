require "fiber"
require "./awaitable"

module AsyncAwait
  module TaskInterface
    include Awaitable

    abstract def proc

    abstract def value_with_csp

    def wait
      wait { }
    end

    def wait
      while status == Status::INCOMPLETE
        yield
      end
    end

    def wait_with_csp
      wait { Fiber.yield }
    end
  end

  class Task(T)
    include TaskInterface
    @value : T?
    getter status : Status
    getter exception : Exception?
    getter proc : ->

    def initialize
      @proc = Proc(Void).new { }
      @status = Status::INCOMPLETE
    end

    def initalize(@value : T)
      @proc = Proc(Void).new { }
      @status = Status::COMPLETE
    end

    def value
      wait
      case @status
      when Status::COMPLETE
        return @value.as(T)
      when Status::FAULT
        raise @exception
      else
        raise "Invalid Task Status"
      end
    end

    def value_with_csp
      wait_with_csp
      case @status
      when Status::COMPLETE
        return @value.as(T)
      when Status::FAULT
        raise @exception
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

    def self.yield : Awaitable
      YieldAwaitable.new
    end

    private class YieldAwaitable
      include Awaitable

      @status = Status::INCOMPLETE

      def value : Nil
      end

      def exception : Nil
      end

      def status
        tmp, @status = @status, Status::COMPLETE
        tmp
      end
    end

    def self.delay(time : Time::Span) : TaskInterface
      TimedTask.new time
    end

    private class TimedTask
      include TaskInterface

      @delay : Time::Span?
      @cur_time = Time.now
      @status = Status::INCOMPLETE

      def initialize(@delay)
      end

      def value : Nil
        wait
      end

      def exception : Nil
      end

      def proc : Nil
      end

      def value_with_csp : Nil
        wait_with_csp
      end

      def status
        delay = @delay.not_nil!
        if delay.ticks != -1 && (Time.now - @cur_time) >= delay
          @status = Status::COMPLETE
        end
        @status
      end
    end
  end
end
