macro async(func)
  {% if func.is_a?(Def) %}
    {% name = func.name %}
    {% if func.receiver %}
      {% name = "#{func.receiver.id}.#{name.id}".id %}
    {% end %}
    {% args = func.args.map do |arg|
         if func.splat_index != nil && arg == func.args[func.splat_index]
           "*#{arg.id}".id
         else
           arg
         end
       end %}
    {% if func.double_splat %}
      {% args = args + ["**#{func.double_splat.id}".id] %}
    {% end %}
    {% if func.block_arg %}
      {% args = args + ["&#{func.block_arg.id}".id] %}
    {% end %}

    def {{name.id}} ({{ args.join(",").id }})
      # Every argument would be wrapped in Proc literal, only
      #  care how to dump and restore local variables correctly
      %task = AsyncAwait.async_call_and_task_builder ->{
        AsyncAwait.current_call.try do |%current|
          %sp = uninitialized Void*

            # get the bottom stack address
            {% if flag?(:x86_64) %}
              asm("movq \%rsp, ($0)":: "r"(pointerof(%sp))::"volatile")
          {% end %}

          %current.sp = %sp
          %current.restore_stack

          AsyncAwait.current_call.try &.current_ip.try do |%ip|
          {% if flag?(:x86_64) %}
            asm("jmp *$0"::"r"(%ip)::"volatile")
          {% end %}
          end
        end

        {{ func.body }}
      }
      %task.proc.call
      %task
    end
  {% else %}
    {{ raise "Only support with explicit methods!" }}
  {% end %}
end
