defmodule JidoDelvetown.ImageGenerationRequests do
  @moduledoc """
  Durable identity and receipts for image generation calls.

  `begin_attempt/2` writes the uncertain state before the provider call. A
  caller must not start another call for an uncertain request. A completed
  request points to the exact staged image artifact and can be reused without
  another provider call.
  """

  import Ecto.Query

  alias JidoDelvetown.ImageGenerator.{Error, Request, Result}
  alias JidoDelvetown.Repo
  alias JidoDelvetown.Storage.{ImageArtifact, ImageGenerationRequest}

  @states ["reserved", "uncertain", "failed", "completed"]
  @max_request_key_bytes 512

  @type reservation :: %{request: map(), reused?: boolean()}

  @doc "Returns one durable generation request, or nil when it is not present."
  @spec get(String.t(), keyword()) :: map() | nil
  def get(request_key, opts \\ [])

  def get(request_key, opts) when is_binary(request_key) and is_list(opts) do
    opts |> repo() |> then(& &1.get(ImageGenerationRequest, request_key)) |> request_view()
  end

  def get(_request_key, _opts), do: nil

  @doc "Rebuilds the validated request stored for a key."
  @spec load_request(String.t(), keyword()) :: {:ok, Request.t()} | {:error, term()}
  def load_request(request_key, opts \\ [])

  def load_request(request_key, opts) when is_binary(request_key) and is_list(opts) do
    case repo(opts).get(ImageGenerationRequest, request_key) do
      nil -> {:error, :generation_request_not_found}
      stored -> restore_request(stored)
    end
  end

  def load_request(_request_key, _opts), do: {:error, :invalid_generation_request_key}

  @doc "Reserves one stable request key before any provider call."
  @spec reserve(String.t(), Request.t() | map() | keyword(), keyword()) ::
          {:ok, reservation()} | {:error, term()}
  def reserve(request_key, request, opts \\ []) when is_list(opts) do
    with :ok <- validate_request_key(request_key),
         {:ok, request} <- Request.new(request) do
      repo = repo(opts)
      reserved_at = now(opts)

      repo.transaction(
        fn -> reserve_transaction(repo, request_key, request, reserved_at) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  @doc "Marks one request uncertain before its remote call starts."
  @spec begin_attempt(String.t(), keyword()) :: {:ok, reservation()} | {:error, term()}
  def begin_attempt(request_key, opts \\ [])

  def begin_attempt(request_key, opts) when is_binary(request_key) and is_list(opts) do
    repo = repo(opts)
    attempted_at = now(opts)

    repo.transaction(
      fn -> begin_attempt_transaction(repo, request_key, attempted_at) end,
      mode: :immediate
    )
    |> transaction_result()
  end

  def begin_attempt(_request_key, _opts), do: {:error, :invalid_generation_request_key}

  @doc "Records a classified failure without hiding an uncertain outcome."
  @spec record_failure(String.t(), Error.t(), keyword()) ::
          {:ok, reservation()} | {:error, term()}
  def record_failure(request_key, error, opts \\ [])

  def record_failure(request_key, %Error{} = error, opts)
      when is_binary(request_key) and is_list(opts) do
    with :ok <- Error.validate(error) do
      repo = repo(opts)

      repo.transaction(
        fn -> record_failure_transaction(repo, request_key, error, now(opts)) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  def record_failure(_request_key, _error, _opts), do: {:error, :invalid_generation_failure}

  @doc "Completes one request with a staged artifact and canonical result receipt."
  @spec complete(String.t(), String.t(), Result.t(), keyword()) ::
          {:ok, reservation()} | {:error, term()}
  def complete(request_key, artifact_digest, result, opts \\ [])

  def complete(request_key, artifact_digest, %Result{} = result, opts)
      when is_binary(request_key) and is_binary(artifact_digest) and is_list(opts) do
    with :ok <- Result.validate(result) do
      repo = repo(opts)

      repo.transaction(
        fn -> complete_transaction(repo, request_key, artifact_digest, result, now(opts)) end,
        mode: :immediate
      )
      |> transaction_result()
    end
  end

  def complete(_request_key, _artifact_digest, _result, _opts),
    do: {:error, :invalid_generation_receipt}

  @doc "Returns counts for all durable generation states."
  @spec counts(keyword()) :: %{atom() => non_neg_integer()}
  def counts(opts \\ []) do
    observed =
      repo(opts).all(
        from(request in ImageGenerationRequest,
          group_by: request.state,
          select: {request.state, count()}
        )
      )
      |> Map.new()

    Map.new(@states, fn state -> {state_atom(state), Map.get(observed, state, 0)} end)
  end

  defp reserve_transaction(repo, request_key, request, reserved_at) do
    case repo.get(ImageGenerationRequest, request_key) do
      nil -> insert_request(repo, request_key, request, reserved_at)
      stored -> validate_existing_request(repo, stored, request)
    end
  end

  defp insert_request(repo, request_key, request, reserved_at) do
    stored =
      %ImageGenerationRequest{
        request_key: request_key,
        request_fingerprint: Request.fingerprint(request),
        provider: request.provider,
        model: request.model,
        prompt: request.prompt,
        options: request_options(request),
        request_metadata: json_safe(request.metadata),
        state: "reserved",
        attempt_count: 0,
        reserved_at: reserved_at,
        inserted_at: reserved_at,
        updated_at: reserved_at
      }
      |> repo.insert!()

    reservation(stored, false)
  end

  defp validate_existing_request(repo, stored, request) do
    if stored.request_fingerprint == Request.fingerprint(request) do
      reservation(stored, true)
    else
      repo.rollback({:generation_request_conflict, :request_fingerprint})
    end
  end

  defp begin_attempt_transaction(repo, request_key, attempted_at) do
    case repo.get(ImageGenerationRequest, request_key) do
      nil ->
        repo.rollback(:generation_request_not_found)

      %{state: "reserved"} = stored ->
        stored
        |> Ecto.Changeset.change(
          state: "uncertain",
          attempt_count: stored.attempt_count + 1,
          attempted_at: attempted_at,
          failure: nil
        )
        |> repo.update!()
        |> reservation(false)

      %{state: "completed"} = stored ->
        reservation(stored, true)

      %{state: "uncertain"} ->
        repo.rollback(:generation_outcome_uncertain)

      %{state: state} ->
        repo.rollback({:invalid_generation_state, state})
    end
  end

  defp record_failure_transaction(repo, request_key, error, recorded_at) do
    case repo.get(ImageGenerationRequest, request_key) do
      nil ->
        repo.rollback(:generation_request_not_found)

      %{state: state} = stored when state in ["reserved", "uncertain"] ->
        target_state = failure_state(error.outcome)

        stored
        |> Ecto.Changeset.change(
          state: target_state,
          failure: failure_map(error),
          completed_at: if(target_state == "failed", do: recorded_at)
        )
        |> repo.update!()
        |> reservation(false)

      %{state: "failed", failure: failure} = stored when not is_nil(failure) ->
        if failure == failure_map(error) do
          reservation(stored, true)
        else
          repo.rollback(:generation_failure_conflict)
        end

      %{state: state} ->
        repo.rollback({:invalid_generation_state, state})
    end
  end

  defp complete_transaction(repo, request_key, artifact_digest, result, completed_at) do
    case repo.get(ImageGenerationRequest, request_key) do
      nil ->
        repo.rollback(:generation_request_not_found)

      %{state: "completed", artifact_digest: ^artifact_digest} = stored ->
        reservation(stored, true)

      %{state: "completed"} ->
        repo.rollback(:generation_receipt_conflict)

      %{state: "uncertain"} = stored ->
        artifact = repo.get(ImageArtifact, artifact_digest)

        with :ok <- validate_completion(stored, artifact, result) do
          {usage, response_metadata} = receipt_maps(result)

          stored
          |> Ecto.Changeset.change(
            state: "completed",
            usage: usage,
            response_metadata: response_metadata,
            failure: nil,
            artifact_digest: artifact_digest,
            completed_at: completed_at
          )
          |> repo.update!()
          |> reservation(false)
        else
          {:error, reason} -> repo.rollback(reason)
        end

      %{state: state} ->
        repo.rollback({:invalid_generation_state, state})
    end
  end

  defp validate_completion(_stored, nil, _result), do: {:error, :generation_artifact_not_found}

  defp validate_completion(stored, artifact, result) do
    expected_digest = "sha256:" <> result.image.digest

    cond do
      result.provenance.request_fingerprint != stored.request_fingerprint ->
        {:error, :generation_request_fingerprint_mismatch}

      result.provenance.provider != stored.provider or result.provenance.model != stored.model ->
        {:error, :generation_provider_mismatch}

      artifact.digest != expected_digest or artifact.bytes != result.image.bytes ->
        {:error, :generation_artifact_mismatch}

      artifact.byte_size != result.image.byte_size or
        artifact.mime_type != result.image.media_type or
        artifact.width != result.image.width or artifact.height != result.image.height ->
        {:error, :generation_artifact_metadata_mismatch}

      true ->
        :ok
    end
  end

  defp receipt_maps(result) do
    usage = result.usage |> Map.from_struct() |> json_safe()

    response_metadata =
      json_safe(%{
        image: %{
          digest: "sha256:" <> result.image.digest,
          byte_size: result.image.byte_size,
          media_type: result.image.media_type,
          width: result.image.width,
          height: result.image.height,
          metadata: result.image.metadata
        },
        provenance: Map.from_struct(result.provenance),
        elapsed_ms: result.elapsed_ms,
        provider: result.provider_metadata
      })

    {usage, response_metadata}
  end

  defp restore_request(stored) do
    options = stored.options || %{}

    attrs = %{
      prompt: stored.prompt,
      provider: stored.provider,
      model: stored.model,
      size: restore_size(Map.get(options, "size")),
      quality: Map.get(options, "quality"),
      output_format: Map.get(options, "output_format"),
      timeout_ms: Map.get(options, "timeout_ms"),
      provider_options: Map.get(options, "provider_options", %{}),
      metadata: stored.request_metadata || %{}
    }

    case Request.new(attrs) do
      {:ok, request} ->
        if Request.fingerprint(request) == stored.request_fingerprint,
          do: {:ok, request},
          else: {:error, :corrupt_generation_request}

      {:error, _error} ->
        {:error, :corrupt_generation_request}
    end
  end

  defp restore_size([width, height]), do: {width, height}
  defp restore_size(value), do: value

  defp request_options(request) do
    request
    |> Request.semantic_map()
    |> Map.drop([:prompt, :provider, :model])
    |> json_safe()
  end

  defp failure_map(error) do
    json_safe(%{
      kind: error.kind,
      message: error.message,
      outcome: error.outcome,
      retryable: error.retryable?,
      provider_status: error.provider_status,
      provider_code: error.provider_code,
      details: error.details
    })
  end

  defp failure_state(:not_started), do: "reserved"
  defp failure_state(:failed), do: "failed"
  defp failure_state(:unknown), do: "uncertain"

  defp reservation(stored, reused?) do
    %{request: request_view(stored), reused?: reused?}
  end

  defp request_view(nil), do: nil

  defp request_view(stored) do
    %{
      key: stored.request_key,
      request_fingerprint: stored.request_fingerprint,
      provider: stored.provider,
      model: stored.model,
      prompt: stored.prompt,
      options: stored.options,
      request_metadata: stored.request_metadata,
      state: state_atom(stored.state),
      attempt_count: stored.attempt_count,
      usage: stored.usage,
      response_metadata: stored.response_metadata,
      failure: stored.failure,
      artifact_digest: stored.artifact_digest,
      reserved_at: stored.reserved_at,
      attempted_at: stored.attempted_at,
      completed_at: stored.completed_at,
      inserted_at: stored.inserted_at,
      updated_at: stored.updated_at
    }
  end

  defp validate_request_key(request_key) when is_binary(request_key) do
    if String.valid?(request_key) and String.trim(request_key) != "" and
         byte_size(request_key) <= @max_request_key_bytes,
       do: :ok,
       else: {:error, :invalid_generation_request_key}
  end

  defp validate_request_key(_request_key), do: {:error, :invalid_generation_request_key}

  defp state_atom("reserved"), do: :reserved
  defp state_atom("uncertain"), do: :uncertain
  defp state_atom("failed"), do: :failed
  defp state_atom("completed"), do: :completed

  defp json_safe(nil), do: nil
  defp json_safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%_{} = value), do: value |> Map.from_struct() |> json_safe()
  defp json_safe(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_safe()
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), json_safe(item)} end)
  end

  defp json_safe(value), do: inspect(value)

  defp transaction_result({:ok, value}), do: {:ok, value}
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
  defp now(opts), do: Keyword.get_lazy(opts, :now, &utc_now/0)
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
