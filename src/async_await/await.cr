macro await(call)
  {% if call.is_a?(Call) %}
    {{call}}.try do |%awaitee|
      AsyncAwait.current_call.try do |%current|
        %current.awaitee = ->%awaitee.status
        %current.set_current_ip

        if %awaitee.status == AAStatus::INCOMPLETE
          %current.dump_stack
          return nil
        end
        AsyncAwait.current_call.try &.clean
      end
      %awaitee.value.itself
    end
  {% else %}
    {{ raise "Unsupported expression for await" }}
  {% end %}
end
