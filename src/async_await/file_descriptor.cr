require "./task"
require "./channel"
require "./task_completion_source"
require "./thread"
require "./async_io"

module AsyncAwait
  class FileDescriptor < ::IO::FileDescriptor
    include AsyncIO

    @read_tasks = Channel(IOTask).new

    @write_tasks = Channel(IOTask).new

    def initialize(@fd : Int32, blocking = false, @edge_triggerable : Bool = false)
      @closed = false
      @read_timed_out = false
      @write_timed_out = false
      unless blocking
        self.blocking = false
      end
    end

    def edge_triggerable
      @edge_triggerable
    end

    def read_timeout
      @read_timeout
    end

    def write_timeout
      @write_timeout
    end

    def resume_read(timeout : Bool)
      tcs = TaskCompletionSource(IOTask).new

      @read_tasks.receive(tcs)

      unless tcs.try_set_exception? Exception.new
        task = tcs.task.value.not_nil!
        task.do_work(self, timeout)
      end

      AAThread.current.add_read_event(self) unless @read_tasks.empty?
    end

    private def unbuffered_read(slice : Bytes)
      cnt = slice.size
      ret_cnt = LibC.read(@fd, slice.pointer(cnt).as(Void*), cnt)
      if ret_cnt != -1
        return ret_cnt
      elsif Errno.value != Errno::EAGAIN
        raise Errno.new "Error reading file"
      end

      task = ReadTask.new(slice, 0, false)
      @read_tasks.send(task)
      AAThread.current.add_read_event(self)

      while task.status.incomplete?
        AAThread.current.event_base.not_nil!.run_once
      end
      task.value
    end

    def to_unsafe
      @fd
    end

    def resume_write(timeout : Bool)
      tcs = TaskCompletionSource(IOTask).new

      @write_tasks.receive(tcs)

      unless tcs.try_set_exception? Exception.new
        task = tcs.task.value.not_nil!
        task.do_work(self, timeout)
      end

      AAThread.current.add_write_event(self) unless @write_tasks.empty?
    end

    private def unbuffered_write(slice : Bytes)
      complete_cnt = 0
      loop do
        cnt = slice.size
        ret_cnt = LibC.write(@fd, slice.pointer(cnt).as(Void*), cnt)

        if ret_cnt != -1
          slice += ret_cnt
          complete_cnt += ret_cnt
          return complete_cnt if slice.size == 0
          next
        elsif Errno.value != Errno::EAGAIN
          raise Errno.new "Error writing file"
        end

        break
      end

      task = WriteTask.new(slice, complete_cnt, true)
      @write_tasks.send(task)
      AAThread.current.add_write_event(self)

      while task.status.incomplete?
        AAThread.current.event_base.not_nil!.run_once
      end
      task.value
    end

    def read_async(slice : Bytes)
      AAThread.current.try do |th|
        th.add_io_proc
        th.add_write_event(self)
      end
      ReadTask.new(slice, 0, false).tap { |task| @read_tasks.send task }
    end

    def write_async(slice : Bytes)
      AAThread.current.try do |th|
        th.add_io_proc
        th.add_write_event(self)
      end
      WriteTask.new(slice, 0, true).tap { |task| @write_tasks.send task }
    end

    private abstract class IOTask < Task(Int32)
      @status = Status::INCOMPLETE
      getter exception : Exception?

      def initialize(@buffer : Bytes, @complete_cnt : Int32, @is_fully : Bool)
      end

      def value : Int32
        wait
        case @status
        when Status::COMPLETED
          return @complete_cnt
        when Status::FAULTED
          raise @exception.not_nil!
        else
          raise InvalidStatus.new
        end
      end

      def value? : Int32?
        wait
        case @status
        when Status::COMPLETED
          return @complete_cnt
        when Status::FAULTED
          return nil
        else
          raise InvalidStatus.new
        end
      end

      def value_with_csp : Int32
        wait_with_csp
        case @status
        when Status::COMPLETED
          return @complete_cnt
        when Status::FAULTED
          raise @exception.not_nil!
        else
          raise InvalidStatus.new
        end
      end

      def value_with_csp? : Int32?
        wait_with_csp
        case @status
        when Status::COMPLETED
          return @complete_cnt
        when Status::FAULTED
          return nil
        else
          raise InvalidStatus.new
        end
      end

      abstract def do_work(fd : FileDescriptor, timeout : Bool)

      @[NoInline]
      def status
        @status
      end
    end

    private class ReadTask < IOTask
      def do_work(fd : FileDescriptor, timeout : Bool)
        raise Timeout.new("read time out") if timeout

        loop do
          cnt = @buffer.size
          ret_cnt = LibC.read(fd, @buffer.pointer(cnt).as(Void*), cnt)

          if ret_cnt != -1
            @complete_cnt += ret_cnt
            @buffer += ret_cnt
            unless @is_fully && @buffer.size != 0 && ret_cnt != 0
              @status = Status::COMPLETED
              return
            end
            next
          end

          if Errno.value == Errno::EAGAIN
            fd.@read_tasks.send self
            return
          else
            raise Errno.new("Error reading file")
          end
        end
      rescue ex
        @exception = ex
        @status = Status::FAULTED
      end
    end

    private class WriteTask < IOTask
      def do_work(fd : FileDescriptor, timeout : Bool)
        return unless status.incomplete?

        raise Timeout.new("write time out") if timeout

        loop do
          cnt = @buffer.size
          ret_cnt = LibC.write(fd.fd, @buffer.pointer(cnt).as(Void*), cnt)

          if ret_cnt != -1
            @complete_cnt += ret_cnt
            @buffer += ret_cnt

            unless @is_fully && @buffer.size != 0 && ret_cnt != 0
              @status = Status::COMPLETED
              return
            end
            next
          end

          if Errno.value == Errno::EAGAIN
            fd.@write_tasks.send self
            return
          else
            raise Errno.new("Error writing file")
          end
        end
      rescue ex
        @exception = ex
        @status = Status::FAULTED
      end
    end
  end
end
