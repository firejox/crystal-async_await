module AsyncAwait
  module AsyncIO
    abstract def read_async(slice : Bytes)
    abstract def write_async(slice : Bytes)

    def read_with_csp(slice : Bytes)
      read_async.value_with_csp
    end

    def write_with_csp(slice : Bytes)
      write_async.value_with_csp
    end
  end
end
