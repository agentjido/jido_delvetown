defmodule JidoDelvetown.ImageGenerator.Error do
  @moduledoc "Classified image generation failure without secret response data."

  @kinds [
    :invalid_request,
    :unsupported,
    :authentication,
    :authorization,
    :rate_limited,
    :timeout,
    :network,
    :provider,
    :invalid_response,
    :adapter_contract,
    :internal
  ]

  @outcomes [:not_started, :failed, :unknown]

  @type kind ::
          :invalid_request
          | :unsupported
          | :authentication
          | :authorization
          | :rate_limited
          | :timeout
          | :network
          | :provider
          | :invalid_response
          | :adapter_contract
          | :internal

  @type outcome :: :not_started | :failed | :unknown

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          outcome: outcome(),
          retryable?: boolean(),
          provider_status: non_neg_integer() | nil,
          provider_code: String.t() | nil,
          details: map()
        }

  defexception kind: :internal,
               message: "image generation failed",
               outcome: :failed,
               retryable?: false,
               provider_status: nil,
               provider_code: nil,
               details: %{}

  @doc "Builds one classified failure."
  @spec new(kind(), String.t(), keyword()) :: t()
  def new(kind, message, opts \\ [])
      when kind in @kinds and is_binary(message) and message != "" and is_list(opts) do
    outcome = Keyword.get(opts, :outcome, :failed)

    unless outcome in @outcomes do
      raise ArgumentError, "invalid image generation outcome: #{inspect(outcome)}"
    end

    %__MODULE__{
      kind: kind,
      message: message,
      outcome: outcome,
      retryable?: Keyword.get(opts, :retryable?, false),
      provider_status: Keyword.get(opts, :provider_status),
      provider_code: Keyword.get(opts, :provider_code),
      details: Keyword.get(opts, :details, %{})
    }
  end

  @doc "Builds a request validation failure that did not call a provider."
  @spec invalid_request(String.t(), map()) :: t()
  def invalid_request(message, details \\ %{}) do
    new(:invalid_request, message, outcome: :not_started, details: details)
  end

  @doc "Builds a timeout failure with an unknown remote outcome."
  @spec timeout() :: t()
  def timeout, do: timeout("image generation timed out", %{})

  @spec timeout(map()) :: t()
  def timeout(details) when is_map(details), do: timeout("image generation timed out", details)

  @spec timeout(String.t(), map()) :: t()
  def timeout(message, details) do
    new(:timeout, message, outcome: :unknown, retryable?: false, details: details)
  end

  @doc "Validates a classified adapter failure."
  @spec validate(t()) :: :ok | {:error, :invalid_error}
  def validate(%__MODULE__{} = error) do
    if error.kind in @kinds and is_binary(error.message) and error.message != "" and
         error.outcome in @outcomes and is_boolean(error.retryable?) and
         valid_status?(error.provider_status) and valid_code?(error.provider_code) and
         is_map(error.details) do
      :ok
    else
      {:error, :invalid_error}
    end
  end

  @doc "Returns true when the adapter cannot prove that the provider did no work."
  @spec uncertain?(t()) :: boolean()
  def uncertain?(%__MODULE__{outcome: :unknown}), do: true
  def uncertain?(%__MODULE__{}), do: false

  defp valid_status?(nil), do: true
  defp valid_status?(status), do: is_integer(status) and status >= 0
  defp valid_code?(nil), do: true
  defp valid_code?(code), do: is_binary(code) and code != ""
end
