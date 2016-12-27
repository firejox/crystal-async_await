require "gc"
require "./task"

module AsyncAwait
  private class AsyncCall
    @[ThreadLocal]
    @@current : self? # current async call

    getter prev : self?                      # the previous async call on the stack
    property current_ip : Void*? = nil       # the next reeentrant adddress
    property local_vars : Void*? = nil       # current local variables dump
    property sp : Void* = Pointer(Void).null # the bottom address of async call
    property fp : Void* = Pointer(Void).null # the top address of async call
    getter task : TaskInterface              # the task of current async call
    property awaitee : Awaitable?            # the task which current async call wait for


    def initialize(@task)
    end

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
      @local_vars = GC.malloc_atomic(@fp.address - @sp.address)
      @local_vars.try &.copy_from(@sp, @fp.address - @sp.address)
    end

    def self.current
      @@current
    end
  end

  def self.current_call
    AsyncCall.current
  end

  def self.async_call_and_task_builder(block : -> R) forall R
    task = Task(R).new
    async_call = AsyncCall.new task
    task.proc = ->{
      begin
        async_call.push
        fp = uninitialized Void*
        {% if flag?(:x86_64) %}
          asm("movq \%rsp, ($0)":: "r"(pointerof(fp))::"volatile")
        {% else %}
          {{ raise "Unsupported platform, only x86_64 is supported" }}
        {% end %}
        async_call.fp = fp
        task.value = block.call
        if async_call.awaitee
          Thread.current.channel.send task.proc
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
