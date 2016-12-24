require "./async_call"

module AsyncAwait
  macro await(call)

    {% if call.is_a?(Call) %}
      begin
        AsyncCall.current.not_nil!.awaitee = {{call}}
        %ip = Pointer(Void).null

        # get proper instruction address for reentrant
        {% if flag?(:x86_64) %}
          asm("1: callq 2f
                  jmp   1b
               2: popq  $0
              ": "=r"(%ip)::"volatile")
        {% else %}
          {{ raise "Unsupported platform, only x86_64 is supported" }}
        {% end %}

        AsyncCall.current.try do |%current|
          %current.current_ip = %ip

          case (%tmp = %current.awaitee.not_nil!).status
          when Status::INCOMPLETE
            %current.dump_stack
            return nil
          when Status::FAULT
            %current.local_vars = nil
            %current.awaitee = nil
            raise %tmp.exception.not_nil!
          when Status::COMPLETE
            %current.local_vars = nil
            %current.awaitee = nil
            %tmp.value
          else
            %current.local_vars = nil
            %current.awaitee = nil
            raise "Invaild Task Status"
          end
        end
      end
    {% end %}
  end
end
