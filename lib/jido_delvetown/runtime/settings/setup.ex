defmodule JidoDelvetown.Settings.Setup do
  @moduledoc """
  Supports the local first-run setup workflow.

  DelveTown credentials are written through the normal settings store, so the
  app password is encrypted before it enters SQLite. Model API keys remain in
  the environment and this module reports only whether the selected provider's
  key is present.
  """

  alias JidoDelvetown.{Session, Settings}
  alias JidoDelvetown.Settings.Connection

  @model_options [
    %{value: "openai:gpt-4o-mini", label: "OpenAI GPT-4o mini"},
    %{value: "openai:gpt-4.1-mini", label: "OpenAI GPT-4.1 mini"},
    %{value: "openai:gpt-5-mini", label: "OpenAI GPT-5 mini"}
  ]
  @safe_autonomy_options [
    %{value: "observe", label: "Observe only"},
    %{value: "review", label: "Review before action"}
  ]

  @type status :: %{
          required(:required?) => boolean(),
          required(:identifier) => String.t(),
          required(:password_configured?) => boolean(),
          required(:decision_model) => String.t(),
          required(:model_options) => [map()],
          required(:autonomy_mode) => String.t(),
          required(:autonomy_options) => [map()],
          required(:llm_key) => map(),
          required(:settings_version) => pos_integer()
        }

  @spec status(keyword()) :: {:ok, status()} | {:error, term()}
  def status(opts \\ []) do
    with {:ok, settings} <- Settings.current(settings_opts(opts)) do
      values = settings.values
      identifier = values.account_identifier || ""
      password_configured? = Connection.credentials_configured?(settings_opts(opts))

      {:ok,
       %{
         required?: identifier == "" or not password_configured?,
         identifier: identifier,
         password_configured?: password_configured?,
         decision_model: values.decision_model,
         model_options: model_options(values.decision_model),
         autonomy_mode: safe_autonomy_mode(values.autonomy_mode),
         autonomy_options: @safe_autonomy_options,
         llm_key: llm_key_status(values.decision_model, env_reader(opts)),
         settings_version: settings.version
       }}
    end
  end

  @spec save(map(), keyword()) :: {:ok, Settings.snapshot()} | {:error, term()}
  def save(params, opts \\ [])

  def save(params, opts) when is_map(params) do
    with {:ok, identifier} <- required_text(params, "identifier"),
         {:ok, password} <- required_text(params, "app_password"),
         {:ok, decision_model} <- allowed_value(params, "decision_model", model_values()),
         {:ok, autonomy_mode} <-
           allowed_value(params, "autonomy_mode", safe_autonomy_values()),
         {:ok, expected_version} <- positive_integer(params, "settings_version") do
      Settings.update(
        %{
          account_identifier: identifier,
          account_app_password: password,
          decision_model: decision_model,
          autonomy_mode: autonomy_mode
        },
        settings_opts(opts) ++
          [
            expected_version: expected_version,
            source: "operator_console_setup",
            metadata: %{"workflow" => "first_run"}
          ]
      )
    end
  end

  def save(_params, _opts), do: {:error, :invalid_setup_input}

  @spec test_connection(keyword()) :: {:ok, map()} | {:error, term()}
  def test_connection(opts \\ []) do
    session = Keyword.get(opts, :session, Session)

    with :ok <- session_call(session, :disconnect),
         {:ok, identity} <- session_call(session, :connect) do
      {:ok, identity}
    end
  end

  @spec model_options() :: [map()]
  def model_options, do: @model_options

  @spec safe_autonomy_options() :: [map()]
  def safe_autonomy_options, do: @safe_autonomy_options

  defp model_options(current) do
    if current in model_values() do
      @model_options
    else
      [%{value: current, label: current <> " (current)"} | @model_options]
    end
  end

  defp model_values, do: Enum.map(@model_options, & &1.value)
  defp safe_autonomy_values, do: Enum.map(@safe_autonomy_options, & &1.value)

  defp safe_autonomy_mode(mode) when mode in ["observe", "review"], do: mode
  defp safe_autonomy_mode(_mode), do: "observe"

  defp llm_key_status("openai:" <> _model, reader) do
    environment = "OPENAI_API_KEY"

    %{
      provider: "OpenAI",
      environment: environment,
      configured?: present?(reader.(environment))
    }
  end

  defp llm_key_status(_model, _reader) do
    %{provider: "Custom provider", environment: nil, configured?: true}
  end

  defp env_reader(opts), do: Keyword.get(opts, :env_reader, &System.get_env/1)

  defp settings_opts(opts), do: Keyword.take(opts, [:repo, :scope])

  defp required_text(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:setup_field_required, key}}
          trimmed -> {:ok, trimmed}
        end

      _value ->
        {:error, {:setup_field_required, key}}
    end
  end

  defp allowed_value(params, key, allowed) do
    case Map.get(params, key) do
      value ->
        if value in allowed,
          do: {:ok, value},
          else: {:error, {:invalid_setup_value, key}}
    end
  end

  defp positive_integer(params, key) do
    case Map.get(params, key) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> {:ok, integer}
          _value -> {:error, {:invalid_setup_value, key}}
        end

      _value ->
        {:error, {:invalid_setup_value, key}}
    end
  end

  defp session_call(session, function) do
    apply(session, function, [])
  rescue
    error -> {:error, {:session_unavailable, error}}
  catch
    :exit, reason -> {:error, {:session_unavailable, reason}}
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
