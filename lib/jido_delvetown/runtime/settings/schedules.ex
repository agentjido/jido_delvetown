defmodule JidoDelvetown.Settings.Schedules do
  @moduledoc "Reads the validated worker schedules stored in SQLite."

  alias JidoDelvetown.Settings

  @entries [
    {:reactive_review_cron, "ReactiveParticipationWorker"},
    {:proactive_review_cron, "ProactiveReviewWorker"},
    {:member_discovery_cron, "MemberDiscoveryWorker"},
    {:friend_sync_cron, "FriendSyncWorker"}
  ]

  @keys Enum.map(@entries, &elem(&1, 0))

  @type snapshot :: %{required(atom()) => String.t()}

  @spec keys() :: [atom()]
  def keys, do: @keys

  @spec current(keyword()) :: {:ok, snapshot()} | {:error, term()}
  def current(opts \\ []) do
    with {:ok, settings} <- Settings.current(opts) do
      {:ok, Map.take(settings.values, @keys)}
    end
  end

  @spec crontab(keyword()) :: {:ok, [{String.t(), module()}]} | {:error, term()}
  def crontab(opts \\ []) do
    with {:ok, schedules} <- current(opts) do
      {:ok,
       Enum.map(@entries, fn {key, worker} ->
         {Map.fetch!(schedules, key), Module.concat(["JidoDelvetown.Workers", worker])}
       end)}
    end
  end
end
