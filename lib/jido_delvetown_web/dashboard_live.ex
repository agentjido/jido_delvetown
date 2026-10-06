defmodule JidoDelvetownWeb.DashboardLive do
  @moduledoc false

  use Phoenix.LiveView

  alias JidoDelvetown.{Automation, ImagePublisher, ManualPublisher}
  alias JidoDelvetownWeb.{DashboardComponents, DashboardSnapshot}

  @refresh_ms 3_000

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    assigns =
      DashboardSnapshot.load()
      |> Map.put(:active_tab, active_tab(params))
      |> Map.put(:publish_notice, nil)
      |> Map.put(:like_publish_notice, nil)
      |> Map.put(:image_publish_notice, nil)

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign(socket, DashboardSnapshot.load())}
  end

  @impl true
  def handle_event("publish_simulated", %{"event_key" => event_key}, socket) do
    notice =
      case publisher().publish(event_key) do
        {:ok, publication} ->
          %{
            kind: "safe",
            text: "The draft was published to DelveTown.",
            uri: map_value(publication, :uri)
          }

        {:error, reason} ->
          %{kind: "attention", text: publish_error(reason), uri: nil}
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "simulated-posts")
     |> assign(:publish_notice, notice)}
  end

  @impl true
  def handle_event("publish_simulated_like", %{"event_key" => event_key}, socket) do
    notice =
      case publisher().publish(event_key) do
        {:ok, publication} ->
          %{
            kind: "safe",
            text: "The like was published to DelveTown.",
            uri: map_value(publication, :target_uri)
          }

        {:error, reason} ->
          %{kind: "attention", text: like_publish_error(reason), uri: nil}
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "simulated-posts")
     |> assign(:like_publish_notice, notice)}
  end

  @impl true
  def handle_event("publish_image", %{"draft_key" => draft_key}, socket) do
    notice =
      case image_publisher().publish_manual(draft_key) do
        {:ok, publication} ->
          %{
            kind: "safe",
            text: "The image draft was published to DelveTown.",
            uri: map_value(publication, :receipt, %{}) |> map_value(:uri)
          }

        {:error, reason} ->
          %{kind: "attention", text: image_publish_error(reason), uri: nil}
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "image-drafts")
     |> assign(:image_publish_notice, notice)}
  end

  @impl true
  def handle_event("run_reactive_review", _params, socket) do
    feedback =
      case review_controller().enqueue_reactive_review() do
        {:ok, review} -> review
        {:error, reason} -> review_error(reason, :reactive)
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "overview")
     |> assign(:reactive_review, feedback)}
  end

  @impl true
  def handle_event("run_proactive_review", _params, socket) do
    feedback =
      case review_controller().enqueue_proactive_review() do
        {:ok, review} -> review
        {:error, reason} -> review_error(reason, :proactive)
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "overview")
     |> assign(:proactive_review, feedback)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard-shell">
      <DashboardComponents.styles {assigns} />
      <DashboardComponents.operational_state {assigns} />
      <DashboardComponents.runtime_health {assigns} />
      <DashboardComponents.memory_and_effects {assigns} />
      <DashboardComponents.scan_and_database_status {assigns} />
      <DashboardComponents.recent_events {assigns} />
      <DashboardComponents.planned_controls {assigns} />
      <DashboardComponents.agent_information {assigns} />
      <DashboardComponents.simulated_actions {assigns} />
      <DashboardComponents.footer {assigns} />
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  defp active_tab(%{"tab" => "simulated-posts"}), do: "simulated-posts"
  defp active_tab(%{"tab" => "image-drafts"}), do: "image-drafts"
  defp active_tab(_params), do: "overview"

  defp publish_error(:manual_publish_disabled),
    do: "Manual publishing is off. Set DELVETOWN_MANUAL_PUBLISH_ENABLED=true and restart."

  defp publish_error(:not_found), do: "The saved simulated draft was not found."
  defp publish_error(:not_simulated), do: "This item is not a simulated draft."
  defp publish_error(:invalid_draft_text), do: "The saved draft text is not valid."
  defp publish_error(:missing_reply_target), do: "The reply target could not be loaded."
  defp publish_error(_reason), do: "DelveTown did not accept the draft. Check the local logs."

  defp like_publish_error(:manual_publish_disabled),
    do: "Manual publishing is off. Set DELVETOWN_MANUAL_PUBLISH_ENABLED=true and restart."

  defp like_publish_error(:not_found), do: "The saved simulated like was not found."
  defp like_publish_error(:not_simulated), do: "This item is not a simulated like."

  defp like_publish_error(reason)
       when reason in [
              :missing_like_target,
              :like_target_mismatch,
              :like_target_changed,
              :like_target_unavailable
            ],
       do: "The target post changed or is no longer available. No like was sent."

  defp like_publish_error({:like_not_eligible, reason}),
    do: "The like is no longer eligible: #{state_label(reason)}. No like was sent."

  defp like_publish_error(_reason),
    do: "DelveTown did not accept the like. Check the local logs."

  defp image_publish_error(:manual_publish_disabled),
    do: "Manual publishing is off. Set DELVETOWN_MANUAL_PUBLISH_ENABLED=true and restart."

  defp image_publish_error(:image_draft_not_found), do: "The saved image draft was not found."
  defp image_publish_error(:artifact_not_found), do: "The saved image file was not found."

  defp image_publish_error({:invalid_draft_state, state}),
    do: "The image draft cannot be published from state #{state}."

  defp image_publish_error(_reason),
    do: "DelveTown did not accept the image draft. Check the local logs."

  defp publisher,
    do: Application.get_env(:jido_delvetown, :manual_publisher, ManualPublisher)

  defp image_publisher,
    do: Application.get_env(:jido_delvetown, :image_publisher, ImagePublisher)

  defp review_controller,
    do: Application.get_env(:jido_delvetown, :reactive_review_controller, Automation)

  defp review_error(:runtime_unavailable, kind) do
    %{
      status: :failed,
      label: "Runtime unavailable",
      detail: "Start the Agent and Oban runtimes before you run a #{kind} review.",
      disabled?: true,
      job_id: nil
    }
  end

  defp review_error({:enqueue_failed, _reason}, _kind) do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The job could not be queued. Check the local logs before you retry.",
      disabled?: false,
      job_id: nil
    }
  end

  defp review_error(_reason, kind),
    do: review_error({:enqueue_failed, :unknown}, kind)

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp state_label(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
