require "c/pthread"
require "./lib_c"
require "./channel"

module AsyncAwait
  class Thread
    @@threads = Set(Thread).new

    @@current_thread_key = uninitialized LibC::PthreadKeyT
    @@key_once : LibC::PthreadOnceT = 0

    @th : LibC::PthreadT?
    @exception : Exception?
    @detached = false

    getter channel = Channel(->).new

    def initialize(&@func : ->)
      @@threads << self

      ret = LibGC.pthread_create(out th, nil, ->(dat : Void*) {
        (dat.as(Thread)).start
      }, self.as(Void*))
      @th = th

      if ret != 0
        @@threads.delete(self)
        raise Errno.new("pthread_create")
      end
    end

    def initialize
      @func = ->{}
      @@threads << self
      @th = LibC.pthread_self
    end

    def finalize
      LibGC.pthread_detach(@th.not_nil!) unless @detached
    end

    def join
      if LibGC.pthread_join(@th.not_nil!, out _ret) != 0
        raise Errno.new("pthread_join")
      end
      @detached = true

      if exception = @exception
        raise exception
      end
    end

    @@main = new

    def self.current
      LibC.pthread_getspecific(@@current_thread_key).as(Thread?) || @@main
    end

    def self.threads
      @@threads
    end

    protected def start
      ret = 0
      LibC.pthread_once(pointerof(@@key_once), -> {
        ret = LibC.pthread_key_create(pointerof(@@current_thread_key), ->(data : Void*) {
          @@threads.delete(data.as(Thread))
        })
      })
      
      raise Errno.new("pthread_key_create") if ret != 0

      LibC.pthread_setspecific(@@current_thread_key, self.as(Void*))

      begin
        @func.call
        while task = @channel.receive
          break if task.status != Status::COMPLETED
        end
        @channel.close
        while task.status == Status::COMPLETED
          task.value.call
          task = @channel.receive
        end
      rescue ex
        @exception = ex
      end
    end
  end
end

alias AAThread = AsyncAwait::Thread

def async_spawn(&block)
  AAThread.new &block
end

