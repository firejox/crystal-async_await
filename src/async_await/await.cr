macro await(call, &block)
  {% if call.is_a?(Call) && block %}
    {% call = "#{call.id} #{block.id}".id %}
  {% end %}
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
end

macro await?(call, &block)
  {% if call.is_a?(Call) && block %}
    {% call = "#{call.id} #{block.id}".id %}
  {% end %}
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
    %awaitee.value?.itself
  end
end
