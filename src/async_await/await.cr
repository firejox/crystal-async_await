macro await(call)
  {% if call.is_a?(Call) %}
    begin
      AsyncAwait.current_call.not_nil!.awaitee = %awaitee = {{call}}
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

      AsyncAwait.current_call.try do |%current|
        %current.current_ip = %ip

        if %awaitee.status == AAStatus::INCOMPLETE
          %current.dump_stack
          return nil
        end
        
        %current.awaitee = nil
        %current.current_ip
        %awaitee.value
      end
    end
  {% else %}
    {{ raise "Unsupported expression for await" }}
  {% end %}
end
