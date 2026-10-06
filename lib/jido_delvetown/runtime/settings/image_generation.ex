defmodule JidoDelvetown.Settings.ImageGeneration do
  @moduledoc """
  Reads the validated image generation policy from SQLite settings.

  `authorize/2` reports the current budget. The caller must pass the returned
  `:daily_limit` to `ImageGenerationRequests.begin_attempt/2`. That function
  applies the limit in the same immediate transaction that starts the request.
  """

  alias JidoDelvetown.{ImageGenerationRequests, Repo, Settings}

  @modes ~w(manual proactive reactive)

  @type mode :: String.t()
  @type snapshot :: %{
          enabled?: boolean(),
          provider: String.t(),
          model: String.t(),
          size: :auto | {pos_integer(), pos_integer()},
          quality: String.t(),
          output_format: :png | :jpeg | :webp,
          timeout_ms: pos_integer(),
          daily_limit: non_neg_integer(),
          allowed_modes: [mode()],
          budget: %{
            used: non_neg_integer(),
            limit: non_neg_integer(),
            remaining: non_neg_integer(),
            since: DateTime.t(),
            resets_at: DateTime.t()
          },
          settings: Settings.settings_reference()
        }

  @spec modes() :: [mode()]
  def modes, do: @modes

  @spec current(keyword()) :: {:ok, snapshot()} | {:error, term()}
  def current(opts \\ []) do
    with {:ok, settings} <- Settings.current(opts),
         {:ok, reference} <- Settings.reference(settings) do
      values = settings.values
      usage = ImageGenerationRequests.daily_usage(request_opts(opts))

      {:ok,
       %{
         enabled?: values.image_generation_enabled,
         provider: values.image_generation_provider,
         model: values.image_generation_model,
         size: size(values.image_generation_size),
         quality: values.image_generation_quality,
         output_format: output_format(values.image_generation_output_format),
         timeout_ms: values.image_generation_timeout_ms,
         daily_limit: values.daily_image_generation_limit,
         allowed_modes: values.image_generation_allowed_modes,
         budget: budget(values.daily_image_generation_limit, usage),
         settings: reference
       }}
    end
  end

  @doc "Returns the active policy when generation is enabled for the source mode."
  @spec authorize(mode(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def authorize(mode, opts \\ [])

  def authorize(mode, opts) when mode in @modes do
    with {:ok, require_budget?} <- require_budget(opts),
         {:ok, policy} <- current(opts),
         :ok <- enabled(policy),
         :ok <- allowed_mode(policy, mode),
         :ok <- available_budget(policy, require_budget?) do
      {:ok, policy}
    end
  end

  def authorize(mode, _opts), do: {:error, {:invalid_image_generation_mode, mode}}

  defp enabled(%{enabled?: true}), do: :ok
  defp enabled(_policy), do: {:error, :image_generation_disabled}

  defp allowed_mode(%{allowed_modes: modes}, mode) do
    if mode in modes,
      do: :ok,
      else: {:error, {:image_generation_mode_not_allowed, mode}}
  end

  defp available_budget(_policy, false), do: :ok

  defp available_budget(%{budget: %{remaining: remaining}}, true) when remaining > 0,
    do: :ok

  defp available_budget(_policy, true), do: {:error, :image_generation_daily_limit_reached}

  defp require_budget(opts) do
    case Keyword.get(opts, :require_budget, true) do
      value when is_boolean(value) -> {:ok, value}
      _value -> {:error, :invalid_image_generation_budget_requirement}
    end
  end

  defp budget(limit, usage) do
    Map.merge(usage, %{
      limit: limit,
      remaining: max(limit - usage.used, 0)
    })
  end

  defp request_opts(opts) do
    [repo: Keyword.get(opts, :repo, Repo), now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)]
  end

  defp size("auto"), do: :auto

  defp size(value) do
    [width, height] = String.split(value, "x", parts: 2)
    {String.to_integer(width), String.to_integer(height)}
  end

  defp output_format("png"), do: :png
  defp output_format("jpeg"), do: :jpeg
  defp output_format("webp"), do: :webp
end
