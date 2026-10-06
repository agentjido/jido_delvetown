defmodule JidoDelvetown.ImageUploader do
  @moduledoc """
  Uploads staged image artifacts with durable, content-addressed retry state.

  An attempt is saved before the remote call. A failed or interrupted call
  stays uncertain, so the exact stored bytes can be sent again after restart.
  """

  alias JidoDelvetown.ImageDrafts
  alias JidoDelvetown.Protocol

  @spec upload(String.t()) :: {:ok, map()} | {:error, term()}
  def upload(digest) when is_binary(digest) do
    upload_with(digest, &Protocol.ensure_writes_enabled/0, &Protocol.upload_blob/2)
  end

  def upload(_digest), do: {:error, :invalid_artifact_digest}

  @spec upload_manual(String.t()) :: {:ok, map()} | {:error, term()}
  def upload_manual(digest) when is_binary(digest) do
    upload_with(
      digest,
      &Protocol.ensure_manual_publish_enabled/0,
      &Protocol.upload_manual_blob/2
    )
  end

  def upload_manual(_digest), do: {:error, :invalid_artifact_digest}

  defp upload_with(digest, permission, upload) do
    with :ok <- permission.(),
         {:ok, prepared} <- ImageDrafts.begin_upload(digest) do
      upload_or_reuse(digest, prepared, upload)
    end
  end

  defp upload_or_reuse(_digest, %{reused?: true, artifact: artifact}, _upload) do
    {:ok, %{blob: artifact.upload_receipt, artifact: artifact, reused?: true}}
  end

  defp upload_or_reuse(digest, %{reused?: false, artifact: artifact}, upload) do
    case upload.(artifact.bytes, artifact.mime_type) do
      {:ok, response} -> save_receipt(digest, response)
      {:error, reason} -> fail_upload(digest, {:transport, safe_reason(reason)})
    end
  end

  defp save_receipt(digest, response) when is_map(response) do
    case value(response, :blob) do
      blob when is_map(blob) ->
        case ImageDrafts.complete_upload(digest, blob) do
          {:ok, artifact} ->
            {:ok, %{blob: artifact.upload_receipt, artifact: artifact, reused?: false}}

          {:error, reason} ->
            fail_upload(digest, reason)
        end

      _other ->
        fail_upload(digest, :missing_blob_receipt)
    end
  end

  defp save_receipt(digest, _response), do: fail_upload(digest, :invalid_upload_response)

  defp fail_upload(digest, reason) do
    failure = %{operation: "upload_blob", reason: safe_reason(reason)}

    case ImageDrafts.record_upload_failure(digest, failure) do
      {:ok, _artifact} -> {:error, {:blob_upload_failed, reason}}
      {:error, save_error} -> {:error, {:blob_upload_failure_not_saved, reason, save_error}}
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp safe_reason(%ProtoRune.XRPC.Error{} = error) do
    error
    |> Map.take([:reason, :message, :http_status, :retry_after])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp safe_reason(reason) when is_atom(reason) or is_binary(reason), do: reason
  defp safe_reason(reason) when is_map(reason), do: reason

  defp safe_reason({kind, reason}) when is_atom(kind),
    do: [Atom.to_string(kind), safe_reason(reason)]

  defp safe_reason(_reason), do: :transport_error
end
