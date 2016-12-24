module AsyncAwait
  enum Status
    INCOMPLETE
    COMPLETE
    FAULT
  end

  module Awaitable
    abstract def value
    abstract def status : Status

    abstract def exception
  end
end
