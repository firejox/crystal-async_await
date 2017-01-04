private def to_timeval(time : Int)
  t = uninitialized LibC::Timeval
  t.tv_sec = typeof(t.tv_sec).new(time)
  t.tv_usec = typeof(t.tv_usec).new(0)
  t
end

private def to_timeval(time : Float)
  t = uninitialized LibC::Timeval
  seconds = typeof(t.tv_sec).new(time)
  useconds = typeof(t.tv_usec).new((time - seconds) * 1e6)
  t.tv_sec = seconds
  t.tv_usec = useconds
  t
end

module Event
  struct Base
    def once_event(s : Int32, flags : LibEvent2::EventFlags, data, timeout, &callback : LibEvent2::Callback)
      t = to_timeval(timeout.not_nil!)
      unless LibEvent2.event_base_once(@base, s, flags, callback, data, pointerof(t)) == 0
        raise "Error scheduling one-time event"
      end
    end

    def once_event(s : Int32, flags : LibEvent2::EventFlags, data, &callback : LibEvent2::Callback)
      unless LibEvent2.event_base_once(@base, s, flags, callback, data, nil) == 0
        raise "Error scheduling one-time event"
      end
    end

    def run_once_nonblock
      LibEvent2.event_base_loop(@base, LibEvent2::EventLoopFlags::Once | LibEvent2::EventLoopFlags::NonBlock)
    end
  end
end
