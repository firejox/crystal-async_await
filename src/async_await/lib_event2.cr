lib LibEvent2
  fun event_base_once(eb : EventBase, s : EvutilSocketT, events : EventFlags, callback : Callback, data : Void*, timeout : LibC::Timeval*) : Int
  fun event_get_base(event : Event) : EventBase
  fun event_base_loopexit(eb : EventBase, tv : LibC::Timeval*) : Int
  fun event_base_loopcontinue(eb : EventBase) : Int
  fun event_base_got_exit(eb : EventBase) : Int
end
