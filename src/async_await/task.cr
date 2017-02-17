require "fiber"
require "atomic"
require "./awaitable"

module AsyncAwait
  # The Interface of `Task`.
  # It provide some method to work with `Fiber`.
  abstract class Task(T)
    include Awaitable

    def self.new
      TaskImpl(T).new
    end

    def self.new(value : T)
      TaskImpl.new value
    end

    def self.from_exception(ex : Exception)
      TaskImpl(T).from_exception ex
    end

    # Returns value when `wait_with_csp` is completed.
    # Raised exception if `status` is faulted.
    abstract def value_with_csp : T

    # Returns value when `wait_with_csp` is completed.
    # Nil if `status` is faulted.
    abstract def value_with_csp? : T?

    # Busy wait for task is completed.
    def wait
      wait_impl { next }
    end

    # Yield block when task is incomplete.
    def wait_impl
      while status.incomplete?
        yield
      end
    end

    # Busy wait by `Fiber#yield`.
    def wait_with_csp
      wait_impl { Fiber.yield }
    end
  end

  private class TaskImpl(T) < Task(T)
    @value : T?
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

    def value?
      wait
      case @status
      when Status::COMPLETED
        return @value.as(T)
      when Status::FAULTED
        return nil
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

    def value_with_csp?
      wait_with_csp
      case @status
      when Status::COMPLETED
        return @value.as(T)
      when Status::FAULTED
        return nil
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

alias Task = AsyncAwait::Task

require "./task/*"
