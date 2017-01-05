module AsyncAwait
  enum Status
    INCOMPLETE
    COMPLETED
    FAULTED
  end

  # Raised if the status of `Task` is invalid.
  class InvalidStatus < ::Exception
    def initialize(msg = "Status is Invalid")
      super(msg)
    end
  end

  module Awaitable
    abstract def value
    abstract def status : Status
    abstract def exception
  end
end

alias Awaitable = AsyncAwait::Awaitable
alias AAStatus = AsyncAwait::Status
