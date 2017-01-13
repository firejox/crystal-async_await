require "thread/mutex"

module AsyncAwait
  abstract class Task
    def self.when_any(*tasks : Task(T))
      self.when_any (tasks.to_a.map &.as(Task(T)))
    end

    def self.when_any(tasks : Array(Task(T)))
      AnyTask.new tasks
    end
  end
end

private class AnyTask(T) < Task(Task(T))
  getter exception : Exception?
  @status = AAStatus::INCOMPLETE
  @task : Task(T)?
  @mutex = Thread::Mutex.new

  def initialize(@tasks : Array(Task(T)))
  end

  def value
    wait
    case @status
    when AAStatus::COMPLETED
      return @task
    else
      raise AsyncAwait::InvalidStatus.new
    end
  end

  def value_with_csp
    wait_with_csp
    case @status
    when Status::COMPLETED
      return @task
    else
      raise AsyncAwait::InvalidStatus.new
    end
  end

  @[NoInline]
  def status
    @mutex.try_lock
    return @status unless @status.incomplete?
    @tasks.each do |task|
      unless task.status.incomplete?
        @task = task
        @mutex.unlock
        return @status = AAStatus::COMPLETED
      end
    end
    @status
  rescue ex
    @status
  end
end
