module AsyncAwait
  class AggregateException < Exception
    alias Exceptions = Exception | Array(Exception)
    @causes : Exceptions?

    def initialize(msg = "Aggrefate Exception", @causes : Exceptions? = nil)
      super(msg)
    end

    def initialize(@causes : Exceptions?)
      super("Aggregate exception")
    end

    def initialize(msg : String, *causes : Exceptions)
      @causes = causes.to_a
    end

    def initialize(*causes : Exceptions)
      super("Aggregate exception")
      @causes = causes.to_a
    end

    def cause
      @causes
    end
  end
end
