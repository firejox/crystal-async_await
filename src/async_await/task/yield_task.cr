module AsyncAwait
  class Task
    def self.yield : Awaitable
      YieldAwaitable.new
    end
  end
end

private class YieldAwaitable
  include Awaitable

  @status = AAStatus::INCOMPLETE

  def value : Nil
  end

  def value? : Nil
  end

  def exception : Nil
  end

  @[NoInline]
  def status
    tmp, @status = @status, AAStatus::COMPLETED
    tmp
  end
end
