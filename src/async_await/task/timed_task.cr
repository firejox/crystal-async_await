module AsyncAwait
  class Task
    def self.delay(time : Time::Span) : TaskInterface
      TimedTask.new time
    end
  end
end

private class TimedTask
  include TaskInterface
  @status = AAStatus::INCOMPLETE
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
      @status = AAStatus::COMPLETED
    end
    @status
  end
end
