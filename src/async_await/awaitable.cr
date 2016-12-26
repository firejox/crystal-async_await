module AsyncAwait
  enum Status
    INCOMPLETE
    COMPLETED
    FAULTED
  end

  module Awaitable
    abstract def value
    abstract def status : Status
    abstract def exception
  end
end

alias Awaitable = AsyncAwait::Awaitable
alias AAStatus = AsyncAwait::Status
