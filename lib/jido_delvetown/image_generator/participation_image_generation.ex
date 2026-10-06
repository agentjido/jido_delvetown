defmodule JidoDelvetown.ParticipationImageGeneration do
  @moduledoc """
  Applies image generation policy to one participation proposal.

  A permitted proposal consumes the separate image generation budget and
  stages a reviewable draft. This module never uploads an image or publishes a
  DelveTown record.
  """

  alias JidoDelvetown.ManualImageGeneration
  alias JidoDelvetown.Settings.ImageGeneration, as: GenerationPolicy

  @modes ~w(proactive reactive)

  @doc "Returns the bounded image policy context supplied to participation planning."
  @spec proposal_context(String.t(), keyword()) :: map()
  def proposal_context(mode, opts \\ [])

  def proposal_context(mode, opts) when mode in @modes and is_list(opts) do
    case GenerationPolicy.authorize(mode, Keyword.put(opts, :require_budget, true)) do
      {:ok, policy} -> allowed_context(mode, policy)
      {:error, reason} -> denied_context(mode, reason)
    end
  end

  def proposal_context(mode, _opts),
    do: denied_context(mode, {:invalid_image_generation_mode, mode})

  @doc "Generates and stages one permitted participation image proposal."
  @spec generate(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(cycle, decision, opts \\ [])

  def generate(%{kind: mode} = cycle, decision, opts)
      when mode in @modes and is_map(decision) and is_list(opts) do
    with :ok <- validate_decision(decision),
         {:ok, candidate_id} <- candidate_id(cycle),
         key = request_key(mode, candidate_id),
         attrs = %{
           key: key,
           prompt: Map.fetch!(decision, :image_prompt),
           caption: Map.fetch!(decision, :text),
           alt_text: Map.fetch!(decision, :image_alt_text)
         },
         generation_opts = Keyword.put(opts, :mode, mode),
         {:ok, plan} <- ManualImageGeneration.plan(attrs, generation_opts) do
      ManualImageGeneration.execute(plan, generation_opts)
    end
  end

  def generate(_cycle, _decision, _opts), do: {:error, :invalid_participation_image_proposal}

  @doc false
  @spec request_key(String.t(), String.t()) :: String.t()
  def request_key(mode, candidate_id) when mode in @modes and is_binary(candidate_id) do
    digest =
      candidate_id
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "participation:#{mode}:#{digest}"
  end

  defp allowed_context(mode, policy) do
    %{
      allowed?: true,
      mode: mode,
      operation: "generate_and_stage_image",
      provider: policy.provider,
      model: policy.model,
      size: display_size(policy.size),
      quality: policy.quality,
      output_format: policy.output_format,
      timeout_ms: policy.timeout_ms,
      daily_budget: policy.budget,
      settings: policy.settings,
      will_generate_and_stage?: true,
      will_upload?: false,
      will_publish?: false
    }
  end

  defp denied_context(mode, reason) do
    %{
      allowed?: false,
      mode: mode,
      reason: reason_code(reason),
      will_generate_and_stage?: false,
      will_upload?: false,
      will_publish?: false
    }
  end

  defp validate_decision(%{
         action: "post",
         text: caption,
         image_prompt: prompt,
         image_alt_text: alt_text
       }) do
    if valid_text?(caption, 300) and valid_text?(prompt, 4_000) and
         valid_text?(alt_text, 1_000),
       do: :ok,
       else: {:error, :invalid_participation_image_proposal}
  end

  defp validate_decision(_decision), do: {:error, :invalid_participation_image_proposal}

  defp candidate_id(%{candidate: %{id: id}}) when is_binary(id) and id != "", do: {:ok, id}
  defp candidate_id(_cycle), do: {:error, :missing_participation_image_candidate}

  defp valid_text?(text, limit),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= limit

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code(_reason), do: "image_generation_policy_denied"

  defp display_size(:auto), do: "auto"
  defp display_size({width, height}), do: "#{width}x#{height}"
end
