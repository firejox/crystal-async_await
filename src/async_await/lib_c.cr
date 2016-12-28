lib LibC
  alias PthreadOnceT = Int
  alias PthreadKeyT = UInt

  @[Raises]
  fun pthread_once(key : PthreadOnceT*, init_routine : -> Void) : Int
  fun pthread_key_create(key : PthreadKeyT*, destructor : Void* -> Void) : Int
  fun pthread_getspecific(key : PthreadKeyT) : Void*
  fun pthread_setspecific(key : PthreadKeyT, value : Void*) : Int
end
