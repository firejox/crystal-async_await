require "./file_descriptor"

module AsyncAwait
  module StdIO
    STDIN  = FileDescriptor.new(0, blocking: LibC.isatty(0) == 0)
    STDOUT = FileDescriptor.new(1, blocking: LibC.isatty(1) == 0).tap { |f| f.flush_on_newline = true }
    STDERR = FileDescriptor.new(2, blocking: LibC.isatty(2) == 0).tap { |f| f.flush_on_new_line = true }
  end
end
