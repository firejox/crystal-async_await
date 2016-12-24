require "atomic"
require "./task"

module AsyncAwait
  enum Status
    MAYCOMPLETE
  end

  class TaskCompletionSource(T)
    getter task = Task(T).new
    @status = Atomic(Status).new Status::INCOMPLETE

    def value=(value : T)
      unless try_set_value? value
        raise "Task is not incomplete"
      end
    end

    def try_set_value?(value : T)
      loop do
        if (tuple = @status.compare_and_set(Status::INCOMPLETE, Status::COMPLETE))[1]
          @task.value = value
          @task.status = Status::COMPLETE
          return true
        elsif tuple[0] != Status::MAYCOMPLETE
          return false
        end
      end
    end

    def exception=(exception : Exception)
      unless try_set_exception? exception
        raise "Task is not incomplete"
      end
    end

    def try_set_exception?(exception : Exception)
      loop do
        if (tuple = @status.compare_and_set(Status::INCOMPLETE, Status::FAULT))[1]
          @task.exception = exception
          @task.status = Status::FAULT
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

    protected def reset
      @status.set Status::INCOMPLETE
    end

    protected def complete_set_value(value : T)
      @status.set Status::COMPLETE
      @task.value = value
      @task.status = Status::COMPLETE
    end

    protected def complete_set_exception(exception : Exception)
      @status.set Status::FAULT
      @task.exception = exception
      @task.status = Status::FAULT
    end
  end
end
