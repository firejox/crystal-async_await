require "c/pthread"
require "event"
require "concurrent/scheduler"
require "./lib_c"
require "./channel"

class Scheduler
  def self.event_base
    @@eb
  end
end

module AsyncAwait
  class Thread
    @@threads = Set(Thread).new

    @@current_thread_key = uninitialized LibC::PthreadKeyT
    @@key_once : LibC::PthreadOnceT = 0

    @th : LibC::PthreadT?
    @exception : Exception?
    @detached = false
    @eb : Event::Base?
    @closed = Atomic(Int32).new 0

    protected getter channel = Channel(->).new

    def initialize(@would_stop : Bool = true, &@func : ->)
      @eb = ::Event::Base.new
      @@threads << self

      ret = LibGC.pthread_create(out th, nil, ->(dat : Void*) {
        (dat.as(typeof(self))).start
      }, self.as(Void*))
      @th = th

      if ret != 0
        raise Errno.new("pthread_create")
      end
    end

    def initialize
      @would_stop = true
      @func = ->{}
      @@threads << self
      @th = LibC.pthread_self
    end

    def event_base
      @eb
    end

    protected def event_base=(@eb : Event::Base)
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

    protected def add_io_proc
      return if is_main?
      @channel.send ->do
        @eb.not_nil!.run_loop
      end
    end

    protected def add_read_event(fd)
      ev_flags = LibEvent2::EventFlags::Read

      if !(timeout = fd.read_timeout) || fd.edge_triggerable
        ev_flags |= LibEvent2::EventFlags::ET if fd.edge_triggerable

        @eb.try &.once_event fd.fd, ev_flags, fd.as(Void*) do |s, flags, data|
          fd_io = data.as(AsyncAwait::FileDescriptor)

          if flags.includes?(LibEvent2::EventFlags::Read)
            fd_io.resume_read false
          elsif flags.includes?(LibEvent2::EventFlags::Timeout)
            fd_io.resume_read true
          end
        end
      else
        @eb.try &.once_event fd.fd, ev_flags, fd.as(Void*), timeout do |s, flags, data|
          fd_io = data.as(AsyncAwait::FileDescriptor)

          if flags.includes?(LibEvent2::EventFlags::Read)
            fd_io.resume_read false
          elsif flags.includes?(LibEvent2::EventFlags::Timeout)
            fd_io.resume_read true
          end
        end
      end
    end

    protected def add_write_event(fd)
      ev_flags = LibEvent2::EventFlags::Write

      if !(timeout = fd.write_timeout) || fd.edge_triggerable
        ev_flags |= LibEvent2::EventFlags::ET if fd.edge_triggerable

        @eb.try &.once_event fd.fd, ev_flags, fd.as(Void*) do |s, flags, data|
          fd_io = data.as(AsyncAwait::FileDescriptor)
          if flags.includes?(LibEvent2::EventFlags::Write)
            fd_io.resume_write false
          elsif flags.includes?(LibEvent2::EventFlags::Timeout)
            fd_io.resume_write true
          end
        end
      else
        @eb.try &.once_event fd.fd, ev_flags, fd.as(Void*), timeout do |s, flags, data|
          fd_io = data.as(AsyncAwait::FileDescriptor)

          if flags.includes?(LibEvent2::EventFlags::Write)
            fd_io.resume_write false
          elsif flags.includes?(LibEvent2::EventFlags::Timeout)
            fd_io.resume_write true
          end
        end
      end
    end

    @@main = new
    @@main.event_base = ::Scheduler.event_base

    LibC.pthread_once(pointerof(@@key_once), ->{
      ret = LibC.pthread_key_create(pointerof(@@current_thread_key), ->(data : Void*) {
        @@threads.delete(data.as(self))
      })
      raise Errno.new("pthread_key_create") if ret != 0
    })
    LibC.pthread_setspecific(@@current_thread_key, @@main.as(Void*))

    def self.current
      LibC.pthread_getspecific(@@current_thread_key).as(self)
    end

    def self.threads
      @@threads
    end

    def is_main?
      self == @@main
    end

    def is_current?
      typeof(self).current == self
    end

    def post(proc)
      return if @closed.get == 1 && !is_current?
      @channel.send proc
      if is_main?
        @eb.try &.once_event -1, LibEvent2::EventFlags::Timeout, @channel.as(Void*) do |s, flags, data|
          ch = data.as(Channel(->))
          ch.receive.value.call
        end
      end
    end

    protected def start
      begin
        LibC.pthread_once(pointerof(@@key_once), ->{
          ret = LibC.pthread_key_create(pointerof(@@current_thread_key), ->(data : Void*) {
            @@threads.delete(data.as(typeof(self)))
          })
          raise Errno.new("pthread_key_create") if ret != 0
        })
        LibC.pthread_setspecific(@@current_thread_key, self.as(Void*))
        LibExt.setup_sigfault_handler

        @func.call

        # run task
        if @would_stop
          while (task = @channel.receive).status.completed?
            task.value.call
          end

          @closed.set 1

          # clean last task
          while task.status.completed?
            task.value.call
            task = @channel.receive
          end
        else
          loop do
            @channel.receive.value.call
          end
        end
      rescue ex
        @exception = ex
      ensure
        @closed.set 1
      end
    end
  end
end

alias AAThread = AsyncAwait::Thread

def async_spawn(&block)
  AAThread.new &block
end
