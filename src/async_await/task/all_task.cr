require "../aggregate_exception"
require "thread/mutex"

module AsyncAwait
  abstract class Task(T)
    def self.when_all(*tasks : Task(T))
      self.when_all (tasks.to_a.map &.as(Task(T)))
    end

    def self.when_all(tasks : Array(Task(T)))
      AllTask.new tasks
    end
  end
end

private class AllTask(T) < Task(T)
  getter exception : Exception?
  @status = AAStatus::INCOMPLETE

  def initialize(@tasks : Array(Task(T)))
  end

  def value : Nil
    wait
    case @status
    when Status::COMPLETED
      return
    when Status::FAULTED
      raise @exception.not_nil!
    else
      raise AsyncAwait::InvalidStatus.new
    end
  end

  def value? : Nil
    wait
    case @status
    when Status::COMPLETED
      return
    when Status::FAULTED
      return
    else
      raise AsyncAwait::InvalidStatus.new
    end
  end

  def value_with_csp : Nil
    wait_with_csp
    case @status
    when Status::COMPLETED
      return
    when Status::FAULTED
      raise @exception.not_nil!
    else
      raise AsyncAwait::InvalidStatus.new
    end
  end

  def value_with_csp? : Nil
    wait_with_csp
    case @status
    when Status::COMPLETED
      return
    when Status::FAULTED
      return
    else
      raise AsyncAwait::InvalidStatus.new
    end
  end

  @[NoInline]
  def status
    return @status unless @status.incomplete?
    return AAStatus::INCOMPLETE if @tasks.any? &.status.incomplete?
    case @tasks
    when .any? &.status.faulted?
      errors = @tasks.reject(&.exception.nil?)
      @exception = AsyncAwait::AggregateException.new errors.map &.exception.not_nil!
      @status = AAStatus::FAULTED
    when .all? &.status.completed?
      @status = AAStatus::COMPLETED
    else
      @exception = AsyncAwait::InvalidStatus.new
      @status = AAStatus::FAULTED
    end
  end
end
