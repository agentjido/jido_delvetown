defmodule JidoDelvetown.Settings.Limits do
  @moduledoc "Reads one validated limit snapshot for a participation cycle."

  alias JidoDelvetown.Settings

  @keys [
    :notification_limit,
    :daily_reply_limit,
    :daily_post_limit,
    :daily_welcome_limit,
    :daily_follow_limit,
    :daily_like_limit,
    :like_actor_cooldown_hours,
    :like_candidate_max_age_hours,
    :member_discovery_limit,
    :member_max_age_hours,
    :friend_sync_limit,
    :conversation_turn_limit,
    :conversation_max_age_hours,
    :conversation_non_response_limit
  ]

  @type snapshot :: %{required(atom()) => non_neg_integer()}

  @spec current(keyword()) :: {:ok, snapshot()} | {:error, term()}
  def current(opts \\ []) do
    with {:ok, settings} <- Settings.current(opts) do
      {:ok, from_settings(settings)}
    end
  end

  @doc "Returns the limit values from one already-read settings snapshot."
  @spec from_settings(Settings.snapshot()) :: snapshot()
  def from_settings(%{values: values}), do: Map.take(values, @keys)

  @spec fetch(atom(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def fetch(key, opts \\ [])

  def fetch(key, opts) when key in @keys do
    with {:ok, limits} <- current(opts) do
      {:ok, Map.fetch!(limits, key)}
    end
  end

  def fetch(key, _opts), do: {:error, {:unknown_limit, key}}

  @spec conversation_policy(keyword()) ::
          {:ok,
           %{
             turn_limit: pos_integer(),
             max_age_hours: pos_integer(),
             non_response_limit: pos_integer()
           }}
          | {:error, term()}
  def conversation_policy(opts \\ []) do
    with {:ok, limits} <- current(opts) do
      {:ok,
       %{
         turn_limit: limits.conversation_turn_limit,
         max_age_hours: limits.conversation_max_age_hours,
         non_response_limit: limits.conversation_non_response_limit
       }}
    end
  end
end
