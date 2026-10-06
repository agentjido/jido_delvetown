defmodule JidoDelvetown.Flow.Imp do
  @moduledoc "Adds one local Imp-backed Step declaration to the Jido Flow DSL."

  use Jido.Flow.Extension

  @allowed_options [:input, :needs, :meta]

  defmacro imp(name, options) do
    caller = __CALLER__
    validate_options!(options, caller)

    input = Keyword.fetch!(options, :input)
    needs = Keyword.get(options, :needs, [])
    meta = Keyword.get(options, :meta, Macro.escape(%{}))

    quote line: caller.line do
      step unquote(name),
        action: JidoDelvetown.Actions.DecideParticipation,
        params: %{cycle: unquote(input)},
        needs: unquote(needs),
        meta: unquote(meta)
    end
  end

  defp validate_options!(options, caller) do
    unless Keyword.keyword?(options) do
      compile_error!(caller, "imp options must be a keyword list")
    end

    duplicates = Keyword.keys(options) -- Enum.uniq(Keyword.keys(options))

    if duplicates != [] do
      compile_error!(caller, "duplicate imp option: #{inspect(hd(duplicates))}")
    end

    case Enum.reject(Keyword.keys(options), &(&1 in @allowed_options)) do
      [] -> :ok
      [option | _rest] -> compile_error!(caller, "unknown imp option: #{inspect(option)}")
    end

    for required <- [:input], not Keyword.has_key?(options, required) do
      compile_error!(caller, "missing imp option: #{inspect(required)}")
    end

    :ok
  end

  defp compile_error!(caller, description) do
    raise CompileError, file: caller.file, line: caller.line, description: description
  end
end
