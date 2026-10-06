defmodule JidoDelvetownWeb.DashboardLive do
  @moduledoc false

  use Phoenix.LiveView

  alias JidoDelvetown.{Automation, DraftReviews, ImagePublisher, ManualPublisher}
  alias JidoDelvetown.Settings.{Console, Setup}
  alias JidoDelvetownWeb.{DashboardComponents, DashboardSettings, DashboardSnapshot}

  @refresh_ms 3_000

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    snapshot = DashboardSnapshot.load()

    assigns =
      snapshot
      |> Map.put(:active_tab, active_tab(params))
      |> Map.put(:show_setup, map_value(snapshot.setup, :required?, false))
      |> Map.put(:setup_notice, nil)
      |> Map.put(:publish_notice, nil)
      |> Map.put(:like_publish_notice, nil)
      |> Map.put(:image_publish_notice, nil)
      |> Map.put(:draft_review_notice, nil)
      |> Map.put(:settings_notice, nil)

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
      case publish_reviewed("text", event_key, fn -> publisher().publish(event_key) end) do
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
     |> assign(:active_tab, "drafts")
     |> assign(:publish_notice, notice)}
  end

  @impl true
  def handle_event("publish_simulated_like", %{"event_key" => event_key}, socket) do
    notice =
      case publish_reviewed("like", event_key, fn -> publisher().publish(event_key) end) do
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
     |> assign(:active_tab, "drafts")
     |> assign(:like_publish_notice, notice)}
  end

  @impl true
  def handle_event("publish_image", %{"draft_key" => draft_key}, socket) do
    notice =
      case publish_reviewed("image", draft_key, fn ->
             image_publisher().publish_manual(draft_key)
           end) do
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
     |> assign(:active_tab, "drafts")
     |> assign(:image_publish_notice, notice)}
  end

  @impl true
  def handle_event(
        "review_draft",
        %{"kind" => kind, "source_key" => source_key, "decision" => decision},
        socket
      ) do
    notice =
      case draft_reviews().decide(kind, source_key, decision) do
        {:ok, review} ->
          %{
            kind: "safe",
            text: "The draft was #{map_value(review, :decision)} in local review memory."
          }

        {:error, reason} ->
          %{kind: "attention", text: draft_review_error(reason)}
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "drafts")
     |> assign(:draft_review_notice, notice)}
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
     |> assign(:active_tab, "inbox")
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
  def handle_event("set_theme", %{"theme" => theme}, socket) do
    case console_settings().select_theme(theme) do
      {:ok, _settings} -> {:noreply, assign(socket, :theme, theme)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("set_theme", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save_settings", %{"settings" => params}, socket) do
    notice =
      case settings_editor().save(params) do
        {:ok, result} -> settings_success_notice(result, :save)
        {:error, reason} -> settings_error_notice(reason)
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "settings")
     |> assign(:settings_notice, notice)}
  end

  def handle_event("save_settings", _params, socket) do
    {:noreply, assign(socket, :settings_notice, settings_error_notice(:invalid_settings_form))}
  end

  @impl true
  def handle_event(
        "rollback_settings",
        %{"target_version" => target_version, "rollback" => params},
        socket
      ) do
    notice =
      case settings_editor().rollback(target_version, params) do
        {:ok, result} -> settings_success_notice(result, :rollback)
        {:error, reason} -> settings_error_notice(reason)
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "settings")
     |> assign(:settings_notice, notice)}
  end

  def handle_event("rollback_settings", _params, socket) do
    {:noreply,
     assign(socket, :settings_notice, settings_error_notice(:invalid_settings_rollback))}
  end

  @impl true
  def handle_event("save_setup", %{"setup" => params}, socket) do
    notice =
      case setup_service().save(params) do
        {:ok, _settings} -> connection_notice(setup_service().test_connection())
        {:error, reason} -> setup_error_notice(reason)
      end

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:active_tab, "overview")
     |> assign(:show_setup, true)
     |> assign(:setup_notice, notice)}
  end

  def handle_event("save_setup", _params, socket),
    do: {:noreply, assign(socket, :setup_notice, setup_error_notice(:invalid_setup_input))}

  @impl true
  def handle_event("test_setup_connection", _params, socket) do
    notice = connection_notice(setup_service().test_connection())

    {:noreply,
     socket
     |> assign(DashboardSnapshot.load())
     |> assign(:show_setup, true)
     |> assign(:setup_notice, notice)}
  end

  @impl true
  def handle_event("open_dashboard", _params, socket) do
    show_setup = map_value(socket.assigns.setup, :required?, true)
    {:noreply, assign(socket, :show_setup, show_setup)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="console-root" data-theme={@theme}>
      <DashboardComponents.styles {assigns} />
      <div class="operator-layout">
        <DashboardComponents.sidebar_navigation {assigns} />
        <div class="operator-workspace">
          <DashboardComponents.mobile_navigation {assigns} />
          <main id="operator-content" class="dashboard-shell">
            <%= if @show_setup do %>
              <DashboardComponents.first_run_setup {assigns} />
            <% else %>
              <DashboardComponents.operational_state {assigns} />
              <DashboardComponents.overview {assigns} />
              <DashboardComponents.inbox {assigns} />
              <DashboardComponents.planned_controls {assigns} />
              <DashboardComponents.agent_information {assigns} />
              <DashboardComponents.drafts {assigns} />
              <DashboardComponents.settings {assigns} />
              <DashboardComponents.footer {assigns} />
            <% end %>
          </main>
        </div>
      </div>
    </div>
    """
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  defp active_tab(%{"tab" => "inbox"}), do: "inbox"
  defp active_tab(%{"tab" => "settings"}), do: "settings"

  defp active_tab(%{"tab" => tab}) when tab in ["drafts", "simulated-posts", "image-drafts"],
    do: "drafts"

  defp active_tab(_params), do: "overview"

  defp publish_reviewed(kind, source_key, publish) do
    if draft_reviews().approved?(kind, source_key),
      do: publish.(),
      else: {:error, :not_approved}
  end

  defp publish_error(:manual_publish_disabled),
    do: "Manual publishing is off. Enable manual_publish_enabled in runtime settings."

  defp publish_error(:not_found), do: "The saved simulated draft was not found."
  defp publish_error(:not_simulated), do: "This item is not a simulated draft."
  defp publish_error(:invalid_draft_text), do: "The saved draft text is not valid."
  defp publish_error(:missing_reply_target), do: "The reply target could not be loaded."
  defp publish_error(:not_approved), do: "Approve this draft before you publish it."
  defp publish_error(_reason), do: "DelveTown did not accept the draft. Check the local logs."

  defp like_publish_error(:manual_publish_disabled),
    do: "Manual publishing is off. Enable manual_publish_enabled in runtime settings."

  defp like_publish_error(:not_found), do: "The saved simulated like was not found."
  defp like_publish_error(:not_simulated), do: "This item is not a simulated like."
  defp like_publish_error(:not_approved), do: "Approve this like before you publish it."

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
    do: "Manual publishing is off. Enable manual_publish_enabled in runtime settings."

  defp image_publish_error(:image_draft_not_found), do: "The saved image draft was not found."
  defp image_publish_error(:artifact_not_found), do: "The saved image file was not found."
  defp image_publish_error(:not_approved), do: "Approve this image before you publish it."

  defp image_publish_error({:invalid_draft_state, state}),
    do: "The image draft cannot be published from state #{state}."

  defp image_publish_error(_reason),
    do: "DelveTown did not accept the image draft. Check the local logs."

  defp publisher,
    do: Application.get_env(:jido_delvetown, :manual_publisher, ManualPublisher)

  defp image_publisher,
    do: Application.get_env(:jido_delvetown, :image_publisher, ImagePublisher)

  defp draft_reviews,
    do: Application.get_env(:jido_delvetown, :draft_reviews, DraftReviews)

  defp review_controller,
    do: Application.get_env(:jido_delvetown, :reactive_review_controller, Automation)

  defp console_settings,
    do: Application.get_env(:jido_delvetown, :console_settings, Console)

  defp setup_service,
    do: Application.get_env(:jido_delvetown, :setup_service, Setup)

  defp settings_editor,
    do: Application.get_env(:jido_delvetown, :dashboard_settings, DashboardSettings)

  defp connection_notice({:ok, identity}) do
    handle = map_value(identity, :handle, "configured account")
    did = map_value(identity, :did)

    %{
      kind: "safe",
      title: "Setup saved and connection verified",
      text: if(did, do: "Connected as @#{handle} · #{did}", else: "Connected as @#{handle}.")
    }
  end

  defp connection_notice({:error, reason}) do
    %{
      kind: "attention",
      title: "Settings saved; connection failed",
      text: connection_error(reason)
    }
  end

  defp setup_error_notice(reason) do
    %{kind: "attention", title: "Setup was not saved", text: setup_error(reason)}
  end

  defp setup_error({:setup_field_required, field}),
    do: "Complete the #{String.replace(field, "_", " ")} field."

  defp setup_error({:invalid_setup_value, "autonomy_mode"}),
    do: "Choose Observe only or Review before action."

  defp setup_error({:invalid_setup_value, field}),
    do: "Choose a valid #{String.replace(field, "_", " ")}."

  defp setup_error({:stale_settings, _expected, _actual}),
    do: "Settings changed in another window. Reload this page and try again."

  defp setup_error(_reason), do: "The local settings could not be saved. Check the local logs."

  defp connection_error({:connection_setting_missing, _key}),
    do: "The saved DelveTown credentials are incomplete."

  defp connection_error(_reason),
    do:
      "DelveTown did not accept the connection. Check the identifier and app password, then retry."

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

  defp draft_review_error(:not_found), do: "The saved draft was not found."
  defp draft_review_error(:not_reviewable), do: "This item is not ready for review."
  defp draft_review_error(:already_published), do: "This draft is already published."
  defp draft_review_error(_reason), do: "The local review decision could not be saved."

  defp settings_success_notice(result, operation) do
    changed = map_value(result, :changed, [])
    activations = map_value(result, :activations, [])

    title =
      case operation do
        :rollback -> "Settings rolled back"
        :save when changed == [] -> "No settings changed"
        :save -> "Settings saved"
      end

    text =
      if changed == [] do
        "The active settings already have these values."
      else
        activation_text =
          activations
          |> Enum.map(&map_value(&1, :label))
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "Changed #{Enum.join(changed, ", ")}. Activation: #{activation_text}."
      end

    %{kind: "safe", title: title, text: text}
  end

  defp settings_error_notice({:settings_activation_failed, :worker_reconcile, _reason} = reason) do
    %{kind: "attention", title: "Settings saved; activation failed", text: settings_error(reason)}
  end

  defp settings_error_notice(reason) do
    %{kind: "attention", title: "Settings were not changed", text: settings_error(reason)}
  end

  defp settings_error({:invalid_form_value, key, :not_an_integer}),
    do: "Enter a whole number for #{settings_field_label(key)}."

  defp settings_error({:invalid_form_value, key, :blank}),
    do: "Complete #{settings_field_label(key)}."

  defp settings_error({:invalid_setting, key, :below_minimum}),
    do: "#{settings_field_label(key)} is below the allowed minimum."

  defp settings_error({:invalid_setting, key, :above_maximum}),
    do: "#{settings_field_label(key)} is above the allowed maximum."

  defp settings_error({:invalid_setting, key, _reason}),
    do: "Enter a valid value for #{settings_field_label(key)}."

  defp settings_error({:invalid_settings_combination, _reason}),
    do: "The non-response limit cannot be greater than the conversation turn limit."

  defp settings_error({:confirmation_required, :autonomy_mode, "autonomous"}),
    do: "Confirm autonomous mode before you save it."

  defp settings_error({:confirmation_required, :mark_notifications_seen, true}),
    do: "Confirm remote notification writes before you save them."

  defp settings_error({:stale_settings, _expected, _actual}),
    do: "Settings changed in another window. Reload this page and try again."

  defp settings_error({:settings_revision_not_found, _version}),
    do: "The selected settings revision no longer exists."

  defp settings_error({:settings_activation_failed, :worker_reconcile, _reason}),
    do: "The values were saved, but the Oban schedules could not be activated. Check the logs."

  defp settings_error(_reason),
    do: "The local settings could not be changed. Check the values and the local logs."

  defp settings_field_label(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
  end

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
