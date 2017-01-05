require "atomic"
require "./task"

module AsyncAwait
  # Represents the producer side of `Task`, providing access to the consumer side via
  # `task` method
  class TaskCompletionSource(T)
    # Raised when set value or error on complete task
    class InvalidOperation < ::Exception
      def initialize(msg = "Task is not incomplete")
        super(msg)
      end
    end

    private module Status
      INCOMPLETE  = 0
      COMPLETED   = 1
      FAULTED     = 2
      MAYCOMPLETE = 3
    end

    getter task = Task(T).new
    @status = Atomic(Int32).new Status::INCOMPLETE

    # Set value on the task. Raise `InvalidOperation` if task is completed.
    #
    # ```
    # tcs = TaskCompletionSource(Int32).new
    # tcs.value = 1
    # tcs.task.value # => 1
    # tcs.value = 2  # raise InvalidOperation
    # ```
    def value=(value : T) : Nil
      unless try_set_value? value
        raise InvalidOperation.new
      end
    end

    # Try set value on the task. Returns `false` if task is completed.
    #
    # ```
    # tcs = TaskCompletionSource(Int32).new
    # tcs.try_set_value? 1 # => true
    # tcs.task.value       # => 1
    # tcs.try_set_value? 2 # => false
    # tcs.task.value       # => 1
    # ```
    def try_set_value?(value : T)
      loop do
        if (tuple = @status.compare_and_set(Status::INCOMPLETE, Status::COMPLETED))[1]
          @task.value = value
          @task.status = AAStatus::COMPLETED
          return true
        elsif tuple[0] != Status::MAYCOMPLETE
          return false
        end
      end
    end

    # Set exception on the task. Raise `InvalidOperation` if task is completed.
    #
    # ```
    # tcs = TaskCompletionSource(Int32).new
    # tcs.exception = Exception.new
    # tcs.exception = Exception.new # raise InvalidOperation
    # ```
    def exception=(exception : Exception) : Nil
      unless try_set_exception? exception
        raise InvalidOperation.new
      end
    end

    # Try set exception on the task. Returns `false` if task is completed.
    #
    # ```
    # tcs = TaskCompletionSource(Int32).new
    # tcs.try_set_exception? Exception.new # => true
    # tcs.try_set_exception? Exception.new # => false
    # ```
    def try_set_exception?(exception : Exception)
      loop do
        if (tuple = @status.compare_and_set(Status::INCOMPLETE, Status::FAULTED))[1]
          @task.exception = exception
          @task.status = AAStatus::FAULTED
          return true
        elsif tuple[0] != Status::MAYCOMPLETE
          return false
        end
      end
    end

    protected def try_complete?
      loop do
        if (tuple = @status.compare_and_set(Status::INCOMPLETE, Status::MAYCOMPLETE))[1]
          return true
        elsif tuple[0] != Status::MAYCOMPLETE
          return false
        end
      end
    end

    protected def reset : Nil
      unless @status.compare_and_set(Status::MAYCOMPLETE, Status::INCOMPLETE)[1]
        raise InvalidOperation.new
      end
    end

    protected def complete_set_value(value : T) : Nil
      unless @status.compare_and_set(Status::MAYCOMPLETE, Status::COMPLETED)[1]
        raise InvalidOperation.new
      end
      @task.value = value
      @task.status = AAStatus::COMPLETED
    end

    protected def complete_set_exception(exception : Exception) : Nil
      unless @status.compare_and_set(Status::MAYCOMPLETE, Status::FAULTED)[1]
        raise InvalidOperation.new
      end
      @task.exception = exception
      @task.status = AAStatus::FAULTED
    end
  end
end

alias TaskCompletionSource = AsyncAwait::TaskCompletionSource
