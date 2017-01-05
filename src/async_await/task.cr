require "fiber"
require "atomic"
require "./awaitable"

module AsyncAwait
  # The Interface of `Task`.
  # It provide some method to work with `Fiber`.
  module TaskInterface
    include Awaitable

    # Returns value when `wait_with_csp` is completed.
    # Raised exception if `status` is faulted.
    abstract def value_with_csp

    # Busy wait for task is completed.
    def wait
      wait { next }
    end

    # Yield block when task is incomplete.
    def wait
      while status.incomplete?
        yield
      end
    end

    # Busy wait by `Fiber#yield`.
    def wait_with_csp
      wait { Fiber.yield }
    end
  end

  class Task(T)
    include TaskInterface
    @value = uninitialized T
    @status : Status
    getter exception : Exception?
    protected property proc : ->

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
        raise InvalidStatus.new
      end
    end

    def start
      @proc.call
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
        raise InvalidStatus.new
      end
    end

    protected def value=(@value : T)
    end

    protected def status=(@status)
    end

    protected def exception=(@exception : Exception)
    end

    def self.from_exception(exception : Exception)
      task = new
      task.exception = exception
      task.status = Status::FAULTED
      task
    end
  end
end

alias TaskInterface = AsyncAwait::TaskInterface
alias Task = AsyncAwait::Task

require "./task/*"
