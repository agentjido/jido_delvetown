defmodule JidoDelvetown.Settings.Behavior do
  @moduledoc """
  Reads agent behavior policy from the active runtime settings.

  Normal participation cycles use the stored autonomy mode:

    * `observe` saves a pending proposal, or a completed simulation when the
      dry-run action setting is on.
    * `review` always saves a pending proposal.
    * `autonomous` can execute an enabled action against DelveTown.

  An explicit review cycle always saves a proposal. It cannot execute an
  action, even when the stored autonomy mode is `autonomous`.
  """

  alias JidoDelvetown.Settings

  @control_actions ~w(acknowledge skip)

  @type action_disposition :: :propose | :simulate | :execute

  @spec decision_model(keyword()) :: {:ok, String.t()} | {:error, term()}
  def decision_model(opts \\ []), do: value(:decision_model, opts)

  @spec decision_model_input(keyword()) :: {:ok, term()} | {:error, term()}
  def decision_model_input(opts \\ []) do
    with {:ok, model} <- decision_model(opts) do
      {:ok, model_input(model)}
    end
  end

  @spec model_input(String.t()) :: term()
  def model_input("openai:" <> model) do
    %{
      id: model,
      model: model,
      provider: :openai,
      base_url: "https://api.openai.com/v1",
      deprecated: false,
      retired: false,
      catalog_only: false,
      aliases: []
    }
  end

  def model_input(model), do: model

  @spec decision_timeout(keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def decision_timeout(opts \\ []), do: value(:decision_timeout_ms, opts)

  @spec autonomy_mode(keyword()) :: {:ok, String.t()} | {:error, term()}
  def autonomy_mode(opts \\ []), do: value(:autonomy_mode, opts)

  @spec writes_enabled?(keyword()) :: boolean()
  def writes_enabled?(opts \\ []) do
    match?({:ok, "autonomous"}, autonomy_mode(opts))
  end

  @doc "Returns how a selected participation action can be applied in this cycle."
  @spec action_disposition(String.t(), keyword()) ::
          {:ok, action_disposition()} | {:error, term()}
  def action_disposition(cycle_mode, opts \\ [])

  def action_disposition("review", _opts), do: {:ok, :propose}

  def action_disposition("normal", opts) do
    with {:ok, autonomy_mode} <- autonomy_mode(opts) do
      disposition(autonomy_mode, opts)
    end
  end

  def action_disposition(cycle_mode, _opts),
    do: {:error, {:invalid_cycle_mode, cycle_mode}}

  @spec manual_publish_enabled?(keyword()) :: boolean()
  def manual_publish_enabled?(opts \\ []), do: enabled?(:manual_publish_enabled, opts)

  @spec dry_run_mark_actioned?(keyword()) :: boolean()
  def dry_run_mark_actioned?(opts \\ []), do: enabled?(:dry_run_mark_actioned, opts)

  @spec mark_notifications_seen?(keyword()) :: boolean()
  def mark_notifications_seen?(opts \\ []), do: enabled?(:mark_notifications_seen, opts)

  @spec enabled_actions(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def enabled_actions(opts \\ []), do: value(:enabled_actions, opts)

  @spec action_enabled?(String.t(), keyword()) :: boolean()
  def action_enabled?(action, opts \\ [])

  def action_enabled?(action, _opts) when action in @control_actions, do: true

  def action_enabled?(action, opts) when is_binary(action) do
    case enabled_actions(opts) do
      {:ok, actions} -> action in actions
      {:error, _reason} -> false
    end
  end

  def action_enabled?(_action, _opts), do: false

  @spec filter_enabled_actions([String.t()], keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def filter_enabled_actions(actions, opts \\ []) when is_list(actions) do
    with {:ok, enabled} <- enabled_actions(opts) do
      {:ok, Enum.filter(actions, &(&1 in @control_actions or &1 in enabled))}
    end
  end

  defp enabled?(key, opts), do: match?({:ok, true}, value(key, opts))

  defp disposition("observe", opts) do
    if dry_run_mark_actioned?(opts), do: {:ok, :simulate}, else: {:ok, :propose}
  end

  defp disposition("review", _opts), do: {:ok, :propose}
  defp disposition("autonomous", _opts), do: {:ok, :execute}
  defp disposition(mode, _opts), do: {:error, {:invalid_autonomy_mode, mode}}

  defp value(key, opts) do
    with {:ok, setting} <- Settings.fetch(key, opts) do
      {:ok, setting.value}
    end
  end
end
