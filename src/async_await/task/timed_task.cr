module AsyncAwait
  abstract class Task
    def self.delay(time : Time::Span)
      TimedTask.new time
    end
  end
end

private class TimedTask < Task(Nil)
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

  @[NoInline]
  def status
    if @delay.ticks != -1 && @delay.ago >= @cur_time
      @status = AAStatus::COMPLETED
    end
    @status
  end
end
