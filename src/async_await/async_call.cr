require "./task"
require "./thread"
require "./intrinsics"

module AsyncAwait
  private class AsyncCall
    @[ThreadLocal]
    @@current : self? # current async call

    getter prev : self?                      # the previous async call on the stack
    property current_ip : Void*? = nil       # the next reeentrant adddress
    property local_vars : Void*? = nil       # current local variables dump
    property sp : Void* = Pointer(Void).null # the bottom address of async call
    property fp : Void* = Pointer(Void).null # the top address of async call
    property awaitee : (-> Status)?          # return the status of which task current async call wait for

    protected def push
      @prev = @@current
      @@current = self
    end

    protected def pop
      @@current = @prev
      @prev = nil
    end

    @[NoInline]
    def restore_stack
      @local_vars.try &.copy_to(@sp, @fp.address - @sp.address)
    end

    @[NoInline]
    def dump_stack
      @local_vars ||= GC.malloc(@fp.address - @sp.address)
      @local_vars.try &.copy_from(@sp, @fp.address - @sp.address)
    end

    @[NoInline]
    def set_current_ip : Nil
      @current_ip = Intrinsics.returnaddress(0)
    end

    @[NoInline]
    def clean
      @awaitee = nil
      @current_ip = nil
    end

    def self.current
      @@current
    end
  end

  def self.current_call
    AsyncCall.current
  end

  # A waiting time to ease the cost of GC
  private ELAPSED_TIME = Time::Span.new(10000)

  # :nodoc:
  def self.async_call_and_task_builder(block : -> R) forall R
    task = Task(R).new
    async_call = AsyncCall.new
    task.proc = ->{
      begin
        async_call.push
        start_time = Time.now
        until ELAPSED_TIME.ago >= start_time
          next if async_call.awaitee.try &.call.incomplete?
          fp = uninitialized Void*
          {% if flag?(:x86_64) %}
              asm("movq \%rsp, $0": "=r"(fp)::"volatile")
          {% elsif flags?(:i686) %}
              asm("movl \%esp, $0": "=r"(fp)::"volatile")
          {% else %}
            {{ raise "Unsupported platform, only x86_64 is supported" }}
          {% end %}
          async_call.fp = fp
          task.value = block.call
          break
        end
        if async_call.awaitee
          AAThread.current.post task.proc
        else
          task.status = Status::COMPLETED
        end
      rescue ex
        task.exception = ex
        task.status = Status::FAULTED
      ensure
        async_call.pop
      end
      nil
    }
    task
  end
end
