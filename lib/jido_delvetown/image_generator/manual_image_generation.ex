defmodule JidoDelvetown.ManualImageGeneration.Plan do
  @moduledoc false

  alias JidoDelvetown.ImageGenerator.Request

  @type t :: %__MODULE__{
          request_key: String.t(),
          draft_id: String.t(),
          caption: String.t(),
          alt_text: String.t(),
          request: Request.t(),
          request_fingerprint: String.t(),
          settings: JidoDelvetown.Settings.settings_reference(),
          budget: map(),
          estimated_provider_calls: 0 | 1,
          reuses_completed_request?: boolean()
        }

  @enforce_keys [
    :request_key,
    :draft_id,
    :caption,
    :alt_text,
    :request,
    :request_fingerprint,
    :settings,
    :budget,
    :estimated_provider_calls,
    :reuses_completed_request?
  ]
  defstruct @enforce_keys
end

defmodule JidoDelvetown.ManualImageGeneration do
  @moduledoc """
  Previews and runs one policy-controlled manual image generation.

  A plan is read-only. Execution reserves a durable request before the provider
  call, applies the daily limit in SQLite, and stages the returned bytes. This
  module does not upload an image or publish a DelveTown record.
  """

  alias JidoDelvetown.{
    ImageDrafts,
    ImageGenerationRequests,
    ImageGenerationStager,
    ImageGenerator
  }

  alias JidoDelvetown.ImageGenerator.{ReqLLMAdapter, Request}
  alias JidoDelvetown.ManualImageGeneration.Plan
  alias JidoDelvetown.Settings.ImageGeneration, as: GenerationPolicy

  @type execution_result :: %{
          draft_id: String.t(),
          generation_request_id: String.t(),
          artifact_digest: String.t(),
          draft_state: String.t(),
          generation_state: atom(),
          provider_call_performed?: boolean(),
          reused?: boolean(),
          uploaded_by_command?: false,
          published_by_command?: false,
          provenance: map(),
          usage: map(),
          settings: JidoDelvetown.Settings.settings_reference()
        }

  @doc "Builds a read-only plan and estimates whether one provider call is needed."
  @spec plan(map() | keyword(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def plan(attrs, opts \\ [])

  def plan(attrs, opts) when (is_map(attrs) or is_list(attrs)) and is_list(opts) do
    with {:ok, input} <- normalize_input(attrs),
         {:ok, initial_policy} <- authorize(opts, false),
         {:ok, request} <- request(input, initial_policy),
         :ok <- ImageGenerationRequests.validate_key(input.key),
         :ok <-
           ImageDrafts.validate_draft_input(input.key, %{
             caption: input.caption,
             alt_text: input.alt_text
           }),
         {:ok, estimate} <- preflight(input, request),
         {:ok, policy} <- authorize(opts, estimate.provider_calls == 1),
         :ok <- same_settings(initial_policy.settings, policy.settings) do
      {:ok,
       %Plan{
         request_key: input.key,
         draft_id: input.key,
         caption: input.caption,
         alt_text: input.alt_text,
         request: request,
         request_fingerprint: Request.fingerprint(request),
         settings: policy.settings,
         budget: policy.budget,
         estimated_provider_calls: estimate.provider_calls,
         reuses_completed_request?: estimate.reuses_completed_request?
       }}
    end
  end

  def plan(_attrs, _opts), do: {:error, :invalid_manual_image_generation_input}

  @doc "Returns safe operation settings for display before execution."
  @spec estimate(Plan.t()) :: map()
  def estimate(%Plan{} = plan) do
    request = plan.request

    %{
      operation: "generate_and_stage_image",
      generation_request_id: plan.request_key,
      draft_id: plan.draft_id,
      provider: request.provider,
      model: request.model,
      size: display_size(request.size),
      quality: request.quality,
      output_format: request.output_format,
      timeout_ms: request.timeout_ms,
      request_fingerprint: plan.request_fingerprint,
      prompt: text_summary(request.prompt),
      caption: text_summary(plan.caption),
      alt_text: text_summary(plan.alt_text),
      daily_budget: plan.budget,
      settings: plan.settings,
      estimated_provider_calls: plan.estimated_provider_calls,
      reuses_completed_request?: plan.reuses_completed_request?,
      will_upload?: false,
      will_publish?: false
    }
  end

  @doc "Executes a confirmed plan and returns its saved draft and provenance."
  @spec execute(Plan.t(), keyword()) :: {:ok, execution_result()} | {:error, term()}
  def execute(plan, opts \\ [])

  def execute(%Plan{} = plan, opts) when is_list(opts) do
    with :ok <- validate_plan(plan),
         :ok <- validate_execution_opts(opts),
         {:ok, policy} <- authorize(opts, false),
         :ok <- same_settings(plan.settings, policy.settings),
         :ok <- request_matches_policy(plan, policy),
         {:ok, reservation} <-
           ImageGenerationRequests.reserve(plan.request_key, plan.request, request_opts(opts)) do
      continue(plan, reservation.request, policy, opts)
    end
  end

  def execute(_plan, _opts), do: {:error, :invalid_manual_image_generation_plan}

  defp continue(plan, %{state: :completed} = request, _policy, _opts) do
    completed_result(plan, request, false, true)
  end

  defp continue(plan, %{state: :reserved}, _policy, opts) do
    with {:ok, policy} <- authorize(opts, true),
         :ok <- same_settings(plan.settings, policy.settings),
         {:ok, started} <-
           ImageGenerationRequests.begin_attempt(
             plan.request_key,
             Keyword.put(request_opts(opts), :daily_limit, policy.daily_limit)
           ) do
      case started.request.state do
        :completed -> completed_result(plan, started.request, false, true)
        :uncertain -> call_and_stage(plan, opts)
        state -> {:error, {:invalid_generation_state, state}}
      end
    end
  end

  defp continue(_plan, %{state: :uncertain}, _policy, _opts),
    do: {:error, :generation_outcome_uncertain}

  defp continue(_plan, %{state: state}, _policy, _opts),
    do: {:error, {:invalid_generation_state, state}}

  defp call_and_stage(plan, opts) do
    generator = Keyword.get(opts, :generator, ReqLLMAdapter)
    generator_options = Keyword.get(opts, :generator_options, [])

    case ImageGenerator.generate(generator, plan.request, generator_options) do
      {:ok, result} -> stage_result(plan, result)
      {:error, error} -> record_failure(plan.request_key, error, opts)
    end
  end

  defp stage_result(plan, result) do
    case ImageGenerationStager.stage(plan.request_key, plan.draft_id, result, %{
           caption: plan.caption,
           alt_text: plan.alt_text
         }) do
      {:ok, staged} -> completed_result(plan, staged.generation_request, true, staged.reused?)
      {:error, reason} -> {:error, {:image_generation_stage_failed, reason}}
    end
  end

  defp record_failure(request_key, error, opts) do
    case ImageGenerationRequests.record_failure(request_key, error, request_opts(opts)) do
      {:ok, _recorded} -> {:error, {:image_generation_failed, error}}
      {:error, reason} -> {:error, {:image_generation_failure_record_failed, error, reason}}
    end
  end

  defp completed_result(plan, request, provider_call_performed?, reused?) do
    with %{artifact: artifact} = draft <- ImageDrafts.get(plan.draft_id),
         true <- artifact.digest == request.artifact_digest,
         true <- draft.caption == plan.caption and draft.alt_text == plan.alt_text,
         %{} = response_metadata <- request.response_metadata,
         %{} = provenance <- map_value(response_metadata, :provenance),
         %{} = usage <- request.usage do
      {:ok,
       %{
         draft_id: draft.key,
         generation_request_id: request.key,
         artifact_digest: artifact.digest,
         draft_state: draft.state,
         generation_state: request.state,
         provider_call_performed?: provider_call_performed?,
         reused?: reused?,
         uploaded_by_command?: false,
         published_by_command?: false,
         provenance: provenance,
         usage: usage,
         settings: plan.settings
       }}
    else
      nil -> {:error, :generation_draft_not_found}
      false -> {:error, :generation_draft_mismatch}
      _value -> {:error, :generation_receipt_incomplete}
    end
  end

  defp preflight(input, request) do
    stored = ImageGenerationRequests.get(input.key)
    draft = ImageDrafts.get(input.key)
    fingerprint = Request.fingerprint(request)

    cond do
      is_nil(stored) and is_nil(draft) ->
        {:ok, %{provider_calls: 1, reuses_completed_request?: false}}

      is_nil(stored) ->
        {:error, :image_draft_key_conflict}

      stored.request_fingerprint != fingerprint ->
        {:error, {:generation_request_conflict, :request_fingerprint}}

      stored.state == :completed ->
        completed_preflight(input, stored, draft)

      stored.state == :reserved and is_nil(draft) ->
        {:ok, %{provider_calls: 1, reuses_completed_request?: false}}

      stored.state == :uncertain ->
        {:error, :generation_outcome_uncertain}

      stored.state == :failed ->
        {:error, {:invalid_generation_state, :failed}}

      true ->
        {:error, :image_draft_key_conflict}
    end
  end

  defp completed_preflight(_input, _stored, nil), do: {:error, :generation_draft_not_found}

  defp completed_preflight(input, stored, draft) do
    if draft.artifact_digest == stored.artifact_digest and draft.caption == input.caption and
         draft.alt_text == input.alt_text do
      {:ok, %{provider_calls: 0, reuses_completed_request?: true}}
    else
      {:error, :generation_draft_mismatch}
    end
  end

  defp request(input, policy) do
    Request.new(%{
      prompt: input.prompt,
      provider: policy.provider,
      model: policy.model,
      size: policy.size,
      quality: policy.quality,
      output_format: policy.output_format,
      timeout_ms: policy.timeout_ms,
      provider_options: %{},
      metadata: %{
        source: "manual_operator",
        draft_id: input.key,
        settings: policy.settings
      }
    })
  end

  defp authorize(opts, require_budget?) do
    opts
    |> settings_opts()
    |> Keyword.put(:require_budget, require_budget?)
    |> then(&GenerationPolicy.authorize("manual", &1))
  end

  defp validate_plan(plan) do
    with {:ok, request} <- Request.new(plan.request),
         true <- Request.fingerprint(request) == plan.request_fingerprint,
         true <- plan.request_key == plan.draft_id,
         :ok <- ImageGenerationRequests.validate_key(plan.request_key),
         :ok <-
           ImageDrafts.validate_draft_input(plan.draft_id, %{
             caption: plan.caption,
             alt_text: plan.alt_text
           }) do
      :ok
    else
      false -> {:error, :invalid_manual_image_generation_plan}
      {:error, _reason} = error -> error
    end
  end

  defp validate_execution_opts(opts) do
    if is_list(Keyword.get(opts, :generator_options, [])),
      do: :ok,
      else: {:error, :invalid_image_generator_options}
  end

  defp request_matches_policy(plan, policy) do
    request = plan.request
    metadata_settings = map_value(request.metadata, :settings) || %{}

    valid? =
      request.provider == policy.provider and request.model == policy.model and
        request.size == policy.size and request.quality == policy.quality and
        request.output_format == policy.output_format and request.timeout_ms == policy.timeout_ms and
        request.provider_options == %{} and
        map_value(request.metadata, :source) == "manual_operator" and
        map_value(request.metadata, :draft_id) == plan.draft_id and
        map_value(metadata_settings, :scope) == policy.settings.scope and
        map_value(metadata_settings, :schema_version) == policy.settings.schema_version and
        map_value(metadata_settings, :version) == policy.settings.version

    if valid?, do: :ok, else: {:error, :manual_image_generation_policy_mismatch}
  end

  defp normalize_input(attrs) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    with {:ok, key} <- required_text(attrs, :key, true),
         {:ok, prompt} <- required_text(attrs, :prompt, false),
         {:ok, caption} <- required_text(attrs, :caption, false),
         {:ok, alt_text} <- required_text(attrs, :alt_text, false) do
      {:ok, %{key: key, prompt: prompt, caption: caption, alt_text: alt_text}}
    end
  rescue
    _error -> {:error, :invalid_manual_image_generation_input}
  end

  defp required_text(attrs, key, trim?) do
    case map_value(attrs, key) do
      value when is_binary(value) ->
        normalized = if trim?, do: String.trim(value), else: value

        if String.trim(normalized) == "",
          do: {:error, {:missing_manual_image_generation_field, key}},
          else: {:ok, normalized}

      _value ->
        {:error, {:missing_manual_image_generation_field, key}}
    end
  end

  defp same_settings(reference, reference), do: :ok
  defp same_settings(_planned, _current), do: {:error, :image_generation_settings_changed}

  defp text_summary(text) do
    %{
      bytes: byte_size(text),
      graphemes: String.length(text),
      sha256: text |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
    }
  end

  defp display_size(:auto), do: "auto"
  defp display_size({width, height}), do: "#{width}x#{height}"
  defp display_size(nil), do: nil

  defp settings_opts(opts), do: Keyword.take(opts, [:repo, :scope, :now])
  defp request_opts(opts), do: Keyword.take(opts, [:repo, :now])

  defp map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
