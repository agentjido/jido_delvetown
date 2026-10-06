defmodule JidoDelvetownWeb.DashboardLiveTest do
  use ExUnit.Case, async: false

  alias JidoDelvetown.SelfPortraitDraft
  alias JidoDelvetownWeb.DashboardLive

  defmodule FakeReviewController do
    def enqueue_reactive_review do
      Application.fetch_env!(:jido_delvetown, :reactive_review_test_result)
    end

    def reactive_review_status do
      Application.fetch_env!(:jido_delvetown, :reactive_review_test_status)
    end

    def enqueue_proactive_review do
      Application.fetch_env!(:jido_delvetown, :proactive_review_test_result)
    end

    def proactive_review_status do
      Application.fetch_env!(:jido_delvetown, :proactive_review_test_status)
    end
  end

  defmodule FakeConsoleSettings do
    def select_theme(theme) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:theme_selected, theme})
      Application.fetch_env!(:jido_delvetown, :console_theme_test_result)
    end
  end

  defmodule FakeSetup do
    def status do
      Application.fetch_env!(:jido_delvetown, :setup_status_test_result)
    end

    def save(params) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:setup_saved, params})
      Application.fetch_env!(:jido_delvetown, :setup_save_test_result)
    end

    def test_connection do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), :setup_connection_tested)
      Application.fetch_env!(:jido_delvetown, :setup_connection_test_result)
    end
  end

  defmodule FakeDraftReviews do
    def decide(kind, source_key, decision) do
      send(
        Application.fetch_env!(:jido_delvetown, :test_owner),
        {:draft_reviewed, kind, source_key, decision}
      )

      Application.fetch_env!(:jido_delvetown, :draft_review_test_result)
    end

    def approved?(_kind, _source_key) do
      Application.get_env(:jido_delvetown, :draft_review_approved, false)
    end
  end

  defmodule FakeDashboardSettings do
    def load do
      Application.fetch_env!(:jido_delvetown, :dashboard_settings_test_status)
    end

    def save(params) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:settings_saved, params})
      Application.fetch_env!(:jido_delvetown, :dashboard_settings_save_result)
    end

    def rollback(version, params) do
      send(
        Application.fetch_env!(:jido_delvetown, :test_owner),
        {:settings_rolled_back, version, params}
      )

      Application.fetch_env!(:jido_delvetown, :dashboard_settings_rollback_result)
    end
  end

  defmodule FakePublisher do
    def publish(event_key) do
      send(Application.fetch_env!(:jido_delvetown, :test_owner), {:draft_published, event_key})
      Application.fetch_env!(:jido_delvetown, :manual_publisher_test_result)
    end
  end

  setup do
    old_controller = Application.get_env(:jido_delvetown, :reactive_review_controller)
    old_result = Application.get_env(:jido_delvetown, :reactive_review_test_result)
    old_status = Application.get_env(:jido_delvetown, :reactive_review_test_status)
    old_proactive_result = Application.get_env(:jido_delvetown, :proactive_review_test_result)
    old_proactive_status = Application.get_env(:jido_delvetown, :proactive_review_test_status)
    old_console_settings = Application.get_env(:jido_delvetown, :console_settings)
    old_theme_result = Application.get_env(:jido_delvetown, :console_theme_test_result)
    old_setup_service = Application.get_env(:jido_delvetown, :setup_service)
    old_setup_status = Application.get_env(:jido_delvetown, :setup_status_test_result)
    old_setup_save = Application.get_env(:jido_delvetown, :setup_save_test_result)
    old_setup_connection = Application.get_env(:jido_delvetown, :setup_connection_test_result)
    old_draft_reviews = Application.get_env(:jido_delvetown, :draft_reviews)
    old_draft_review_result = Application.get_env(:jido_delvetown, :draft_review_test_result)
    old_draft_review_approved = Application.get_env(:jido_delvetown, :draft_review_approved)
    old_manual_publisher = Application.get_env(:jido_delvetown, :manual_publisher)
    old_dashboard_settings = Application.get_env(:jido_delvetown, :dashboard_settings)

    old_dashboard_settings_status =
      Application.get_env(:jido_delvetown, :dashboard_settings_test_status)

    old_dashboard_settings_save =
      Application.get_env(:jido_delvetown, :dashboard_settings_save_result)

    old_dashboard_settings_rollback =
      Application.get_env(:jido_delvetown, :dashboard_settings_rollback_result)

    old_manual_publisher_result =
      Application.get_env(:jido_delvetown, :manual_publisher_test_result)

    old_test_owner = Application.get_env(:jido_delvetown, :test_owner)

    Application.put_env(:jido_delvetown, :reactive_review_controller, FakeReviewController)
    Application.put_env(:jido_delvetown, :console_settings, FakeConsoleSettings)
    Application.put_env(:jido_delvetown, :console_theme_test_result, {:ok, %{}})
    Application.put_env(:jido_delvetown, :setup_service, FakeSetup)
    Application.put_env(:jido_delvetown, :setup_status_test_result, {:ok, setup_status(false)})
    Application.put_env(:jido_delvetown, :setup_save_test_result, {:ok, %{}})

    Application.put_env(
      :jido_delvetown,
      :setup_connection_test_result,
      {:ok, %{did: "did:plc:agent", handle: "agent.test"}}
    )

    Application.put_env(:jido_delvetown, :test_owner, self())
    Application.put_env(:jido_delvetown, :draft_reviews, FakeDraftReviews)
    Application.put_env(:jido_delvetown, :manual_publisher, FakePublisher)
    Application.put_env(:jido_delvetown, :dashboard_settings, FakeDashboardSettings)

    Application.put_env(
      :jido_delvetown,
      :dashboard_settings_test_status,
      {:ok, settings_assigns()}
    )

    Application.put_env(
      :jido_delvetown,
      :dashboard_settings_save_result,
      {:ok,
       %{
         changed: ["Daily reply limit"],
         activations: [%{key: :next_cycle, label: "Next cycle"}]
       }}
    )

    Application.put_env(
      :jido_delvetown,
      :dashboard_settings_rollback_result,
      {:ok,
       %{
         changed: ["Daily reply limit"],
         activations: [%{key: :next_cycle, label: "Next cycle"}],
         target_version: 1
       }}
    )

    Application.put_env(
      :jido_delvetown,
      :manual_publisher_test_result,
      {:ok, %{uri: "at://did:plc:agent/town.delve.feed.post/published"}}
    )

    Application.put_env(
      :jido_delvetown,
      :draft_review_test_result,
      {:ok, %{decision: "approved"}}
    )

    Application.put_env(
      :jido_delvetown,
      :reactive_review_test_result,
      {:ok, review_feedback(:queued)}
    )

    Application.put_env(
      :jido_delvetown,
      :reactive_review_test_status,
      review_feedback(:idle)
    )

    Application.put_env(
      :jido_delvetown,
      :proactive_review_test_result,
      {:ok, review_feedback(:queued)}
    )

    Application.put_env(
      :jido_delvetown,
      :proactive_review_test_status,
      review_feedback(:idle)
    )

    on_exit(fn ->
      restore_env(:reactive_review_controller, old_controller)
      restore_env(:reactive_review_test_result, old_result)
      restore_env(:reactive_review_test_status, old_status)
      restore_env(:proactive_review_test_result, old_proactive_result)
      restore_env(:proactive_review_test_status, old_proactive_status)
      restore_env(:console_settings, old_console_settings)
      restore_env(:console_theme_test_result, old_theme_result)
      restore_env(:setup_service, old_setup_service)
      restore_env(:setup_status_test_result, old_setup_status)
      restore_env(:setup_save_test_result, old_setup_save)
      restore_env(:setup_connection_test_result, old_setup_connection)
      restore_env(:draft_reviews, old_draft_reviews)
      restore_env(:draft_review_test_result, old_draft_review_result)
      restore_env(:draft_review_approved, old_draft_review_approved)
      restore_env(:manual_publisher, old_manual_publisher)
      restore_env(:manual_publisher_test_result, old_manual_publisher_result)
      restore_env(:dashboard_settings, old_dashboard_settings)
      restore_env(:dashboard_settings_test_status, old_dashboard_settings_status)
      restore_env(:dashboard_settings_save_result, old_dashboard_settings_save)
      restore_env(:dashboard_settings_rollback_result, old_dashboard_settings_rollback)
      restore_env(:test_owner, old_test_owner)
    end)

    :ok
  end

  test "renders the operator overview" do
    html = render_dashboard()

    assert html =~ "AgentJido"
    assert html =~ ~s(data-theme="system")
    assert html =~ ~s(id="console-theme")
    assert html =~ ~s(phx-change="set_theme")
    assert html =~ "Safe: writes off"
    assert html =~ ~s(class="operator-layout")
    assert html =~ ~s(id="operator-sidebar")
    assert html =~ ~s(id="mobile-console-header")
    assert html =~ ~s(id="operator-content")
    assert html =~ "Inbox"
    assert html =~ "Drafts &amp; approvals"
    assert html =~ "People"
    assert html =~ "Activity"
    assert html =~ "Settings"
    assert html =~ ~s(id="overview-tab")
    assert html =~ ~s(aria-current="page")
    assert html =~ ~s(aria-label="Global agent state")
    assert html =~ ~s(role="switch")
    assert html =~ ~s(aria-checked="false")
    assert html =~ ">OFF</strong>"
    assert html =~ "Autonomy"
    assert html =~ "Observe"
    assert html =~ "Connection"
    assert html =~ "Signed in as @agentjido.test"
    assert html =~ "Next scheduled work"
    assert html =~ "Inbox review"
    assert html =~ "Needs attention"
    assert html =~ "1 effect needs reconciliation"
    assert html =~ "Participation budget"
    assert html =~ "Replies and reposts"
    assert html =~ ~s(role="progressbar")
    assert html =~ "Recent actions"
    assert html =~ "Direct technical question"
    refute html =~ "Approve human-in-the-loop post"
    assert html =~ ~s(id="run-proactive-review")
    assert html =~ ~s(phx-click="run_proactive_review")
    assert html =~ ~s(id="proactive-review-feedback")
    assert html =~ "AgentJido profile"
    assert html =~ "Proposed thread"
    assert html =~ "Published reply"
    assert html =~ "https://delve.town/profile/agentjido.test"
    assert html =~ "3mx4w2xzwzjzs"
    assert html =~ "published-reply"
    assert html =~ "disabled"
    assert function_exported?(DashboardLive, :handle_event, 3)
  end

  test "renders the participation inbox with manual scan and proposals" do
    html = render_dashboard(Map.put(base_assigns(), :active_tab, "inbox"))

    assert html =~ ~s(<h1 id="page-title">Participation inbox</h1>)
    assert html =~ ~s(id="inbox-tab" class="operator-nav-link active")
    assert html =~ ~s(id="inbox-panel")
    assert html =~ "Replies"
    assert html =~ "Mentions"
    assert html =~ "Follows"
    assert html =~ "Likes"
    assert html =~ "@member.test"
    assert html =~ "A supervisor gives this failure boundary one owner."
    assert html =~ "The thread asks a direct technical question."
    assert html =~ "1 need attention"
    assert html =~ "1 proposal"
    assert html =~ "Last completed scan: Oct 05 · 11:59 UTC"
    assert html =~ "Ready for review"
    assert html =~ "current dry-run settings"
    assert html =~ ~s(id="run-reactive-review")
    assert html =~ ~s(phx-click="run_reactive_review")
    assert html =~ "Scan DelveTown now"
    refute html =~ ~s(id="overview-panel")
  end

  test "renders the runtime settings editor and revision history" do
    html = render_dashboard(Map.put(base_assigns(), :active_tab, "settings"))

    assert html =~ ~s(<h1 id="page-title">Runtime settings</h1>)
    assert html =~ ~s(id="settings-tab" class="operator-nav-link active")
    assert html =~ ~s(id="settings-panel")
    assert html =~ ~s(id="runtime-settings-form")
    assert html =~ ~s(phx-submit="save_settings")
    assert html =~ ~s(name="settings[account_app_password]")
    assert html =~ ~s(type="password")
    assert html =~ ~s(name="settings[enabled_actions][]")
    assert html =~ ~s(name="settings[confirm_autonomous]")
    assert html =~ "After worker sync"
    assert html =~ "After restart"
    assert html =~ "Revision history"
    assert html =~ ~s(phx-submit="rollback_settings")
    assert html =~ "Roll back to v2"
    assert html =~ "The current app password will stay unchanged"
    refute html =~ ~s(id="overview-panel")
  end

  test "saves settings and reports validation errors" do
    params = %{"version" => "3", "daily_reply_limit" => "8"}

    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())
      |> Phoenix.Component.assign(:active_tab, "settings")

    assert {:noreply, saved_socket} =
             DashboardLive.handle_event("save_settings", %{"settings" => params}, socket)

    assert_received {:settings_saved, ^params}
    assert saved_socket.assigns.active_tab == "settings"
    assert saved_socket.assigns.settings_notice.title == "Settings saved"
    assert saved_socket.assigns.settings_notice.text =~ "Daily reply limit"
    assert saved_socket.assigns.settings_notice.text =~ "Next cycle"

    Application.put_env(
      :jido_delvetown,
      :dashboard_settings_save_result,
      {:error, {:invalid_form_value, :daily_reply_limit, :not_an_integer}}
    )

    assert {:noreply, error_socket} =
             DashboardLive.handle_event("save_settings", %{"settings" => params}, saved_socket)

    assert error_socket.assigns.settings_notice.kind == "attention"
    assert error_socket.assigns.settings_notice.text =~ "whole number"
  end

  test "rolls settings back through the editor service" do
    params = %{"version" => "3", "confirm_autonomous" => "true"}

    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())
      |> Phoenix.Component.assign(:active_tab, "settings")

    assert {:noreply, rolled_back_socket} =
             DashboardLive.handle_event(
               "rollback_settings",
               %{"target_version" => "2", "rollback" => params},
               socket
             )

    assert_received {:settings_rolled_back, "2", ^params}
    assert rolled_back_socket.assigns.active_tab == "settings"
    assert rolled_back_socket.assigns.settings_notice.title == "Settings rolled back"
  end

  test "renders first-run setup without accepting an LLM key" do
    assigns =
      base_assigns()
      |> Map.put(:show_setup, true)
      |> Map.put(:setup, setup_status(true, llm_key_configured?: false))

    html = render_dashboard(assigns)

    assert html =~ ~s(id="first-run-setup")
    assert html =~ "Connect AgentJido"
    assert html =~ ~s(id="setup-identifier")
    assert html =~ ~s(id="setup-app-password")
    assert html =~ ~s(type="password")
    assert html =~ "encrypted before it is saved"
    assert html =~ ~s(id="setup-decision-model")
    assert html =~ "OPENAI_API_KEY"
    assert html =~ "Not detected"
    assert html =~ ~s(value="observe")
    assert html =~ ~s(value="review")
    refute html =~ ~s(value="autonomous")
    refute html =~ ~s(name="setup[openai_api_key]")
    assert html =~ ~s(phx-submit="save_setup")
    assert html =~ "Save and test connection"
    refute html =~ ~s(id="overview-panel")
  end

  test "saves setup, tests the connection, and opens the dashboard" do
    params = %{
      "identifier" => "agent.test",
      "app_password" => "app-password",
      "decision_model" => "openai:gpt-4o-mini",
      "autonomy_mode" => "observe",
      "settings_version" => "1"
    }

    Application.put_env(
      :jido_delvetown,
      :setup_status_test_result,
      {:ok, setup_status(false)}
    )

    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())
      |> Phoenix.Component.assign(:show_setup, true)

    assert {:noreply, saved_socket} =
             DashboardLive.handle_event("save_setup", %{"setup" => params}, socket)

    assert_received {:setup_saved, ^params}
    assert_received :setup_connection_tested
    assert saved_socket.assigns.show_setup
    assert saved_socket.assigns.setup_notice.kind == "safe"

    saved_html = render_dashboard(saved_socket.assigns)
    assert saved_html =~ "Setup saved and connection verified"
    assert saved_html =~ "@agent.test"
    assert saved_html =~ ~s(phx-click="open_dashboard")

    assert {:noreply, dashboard_socket} =
             DashboardLive.handle_event("open_dashboard", %{}, saved_socket)

    refute dashboard_socket.assigns.show_setup
    assert render_dashboard(dashboard_socket.assigns) =~ ~s(id="overview-panel")
  end

  test "keeps saved setup visible when the connection test fails" do
    Application.put_env(
      :jido_delvetown,
      :setup_status_test_result,
      {:ok, setup_status(false, password_configured?: true)}
    )

    Application.put_env(
      :jido_delvetown,
      :setup_connection_test_result,
      {:error, :invalid_credentials}
    )

    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())
      |> Phoenix.Component.assign(:show_setup, true)

    assert {:noreply, updated_socket} =
             DashboardLive.handle_event(
               "save_setup",
               %{
                 "setup" => %{
                   "identifier" => "agent.test",
                   "app_password" => "wrong-password",
                   "decision_model" => "openai:gpt-4o-mini",
                   "autonomy_mode" => "observe",
                   "settings_version" => "1"
                 }
               },
               socket
             )

    html = render_dashboard(updated_socket.assigns)
    assert updated_socket.assigns.show_setup
    assert html =~ "Settings saved; connection failed"
    assert html =~ "Retry DelveTown connection"
    refute html =~ ~s(phx-click="open_dashboard")
  end

  test "changes the console theme and keeps an invalid selection unchanged" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())

    assert {:noreply, updated_socket} =
             DashboardLive.handle_event("set_theme", %{"theme" => "dark"}, socket)

    assert_received {:theme_selected, "dark"}
    assert updated_socket.assigns.theme == "dark"
    assert render_dashboard(updated_socket.assigns) =~ ~s(data-theme="dark")

    Application.put_env(
      :jido_delvetown,
      :console_theme_test_result,
      {:error, {:invalid_setting, :console_theme, :not_allowed}}
    )

    assert {:noreply, unchanged_socket} =
             DashboardLive.handle_event("set_theme", %{"theme" => "sepia"}, updated_socket)

    assert_received {:theme_selected, "sepia"}
    assert unchanged_socket.assigns.theme == "dark"
  end

  test "reports queued, duplicate, unavailable, and worker-failure review results" do
    cases = [
      {{:ok, review_feedback(:queued)}, "queued", "Review queued"},
      {{:ok, review_feedback(:skipped)}, "skipped", "Review already queued"},
      {{:error, :runtime_unavailable}, "failed", "Runtime unavailable"},
      {{:ok, review_feedback(:failed)}, "failed", "Review failed"}
    ]

    for {result, status, label} <- cases do
      Application.put_env(:jido_delvetown, :reactive_review_test_result, result)

      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(base_assigns())

      assert {:noreply, updated_socket} =
               DashboardLive.handle_event("run_reactive_review", %{}, socket)

      assert updated_socket.assigns.reactive_review.status == String.to_existing_atom(status)
      assert updated_socket.assigns.active_tab == "inbox"

      html = render_dashboard(updated_socket.assigns)
      assert html =~ ~s(data-status="#{status}")
      assert html =~ label
    end
  end

  test "reports all manual proactive review states and keeps matching work disabled" do
    cases = [
      {{:ok, review_feedback(:queued)}, :queued, "Review queued", true},
      {{:ok, review_feedback(:running)}, :running, "Review running", true},
      {{:ok, review_feedback(:completed)}, :completed, "Review completed", false},
      {{:ok, review_feedback(:skipped)}, :skipped, "Review already queued", true},
      {{:error, :runtime_unavailable}, :failed, "Runtime unavailable", true},
      {{:ok, review_feedback(:failed)}, :failed, "Review failed", true}
    ]

    for {result, status, label, disabled?} <- cases do
      Application.put_env(:jido_delvetown, :proactive_review_test_result, result)

      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(base_assigns())

      assert {:noreply, updated_socket} =
               DashboardLive.handle_event("run_proactive_review", %{}, socket)

      assert updated_socket.assigns.proactive_review.status == status
      assert updated_socket.assigns.proactive_review.disabled? == disabled?

      html = render_dashboard(updated_socket.assigns)
      assert html =~ ~s(id="proactive-review-feedback")
      assert html =~ ~s(data-status="#{status}")
      assert html =~ label
    end
  end

  test "stores a local draft review decision and returns to the drafts view" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())

    assert {:noreply, updated_socket} =
             DashboardLive.handle_event(
               "review_draft",
               %{
                 "kind" => "text",
                 "source_key" => "event:simulated-reply",
                 "decision" => "approved"
               },
               socket
             )

    assert_received {:draft_reviewed, "text", "event:simulated-reply", "approved"}
    assert updated_socket.assigns.active_tab == "drafts"
    assert updated_socket.assigns.draft_review_notice.kind == "safe"
    assert updated_socket.assigns.draft_review_notice.text =~ "approved"
  end

  test "requires local approval before the publish handler runs" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(base_assigns())

    refute Application.get_env(:jido_delvetown, :draft_review_approved, false)

    assert {:noreply, blocked_socket} =
             DashboardLive.handle_event(
               "publish_simulated",
               %{"event_key" => "event:simulated-reply"},
               socket
             )

    refute_received {:draft_published, _event_key}
    assert blocked_socket.assigns.publish_notice.kind == "attention"
    assert blocked_socket.assigns.publish_notice.text =~ "Approve this draft"

    Application.put_env(:jido_delvetown, :draft_review_approved, true)

    assert {:noreply, published_socket} =
             DashboardLive.handle_event(
               "publish_simulated",
               %{"event_key" => "event:simulated-reply"},
               socket
             )

    assert_received {:draft_published, "event:simulated-reply"}
    assert published_socket.assigns.publish_notice.kind == "safe"
  end

  test "renders durable simulated drafts in the simulated posts tab" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :simulated_posts], [
        %{
          event_key: "event:simulated-reply",
          action: "reply",
          text: "Give & keep each failure boundary <small>.",
          topic: "OTP",
          reason: "A direct technical question",
          response_format: "state_machine_sketch",
          intent: "answer_direct_request",
          record_uri: "at://did:plc:member/town.delve.feed.post/source-post",
          simulated_at: "2026-10-05T12:04:00Z",
          review: %{state: "approved"}
        }
      ])
      |> put_in([:drafts, :approved_count], 1)
      |> put_in([:drafts, :type_counts, :text], 1)

    html = render_dashboard(assigns)

    assert html =~ ~s(id="drafts-panel")
    assert html =~ "Local review queue"
    assert html =~ "Manual publish ready"
    assert html =~ "Give &amp; keep each failure boundary &lt;small&gt;."
    assert html =~ "State machine sketch"
    assert html =~ "source-post"
    assert html =~ "Manual publish ready"
    assert html =~ "Publish to DelveTown"
    assert html =~ ~s(phx-click="publish_simulated")
    assert html =~ ~s(phx-value-event_key="event:simulated-reply")
    refute html =~ "phx-value-event-key"
    refute html =~ ~s(disabled="")
    refute html =~ ~s(id="overview-panel")
  end

  test "replaces the publish button with the saved publication link" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :simulated_posts], [
        %{
          event_key: "event:published-reply",
          action: "reply",
          text: "This draft is now public.",
          published_status: "completed",
          published_uri: "at://did:plc:agentjido/town.delve.feed.post/published-rkey"
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published"
    assert html =~ "View published post"
    assert html =~ "/profile/agentjido.test/post/published-rkey"
    refute html =~ "Publish to DelveTown"
  end

  test "shows the simulated-post empty state" do
    html = render_dashboard(Map.put(base_assigns(), :active_tab, "drafts"))

    assert html =~ ~s(<h1 id="page-title">Drafts &amp; approvals</h1>)
    assert html =~ ~s(id="drafts-panel")
    assert html =~ "No post or reply draft is waiting for review"
    assert html =~ "Approval and rejection are local"
    assert html =~ "SQLite decisions"
  end

  test "shows like proposals as bodyless review cards with clear terminal state" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :like_proposals], [
        %{
          event_key: "like:simulated",
          event_state: "completed",
          proposal_status: "simulated",
          publication_state: "simulated",
          target_uri: "at://did:plc:author/town.delve.feed.post/target-one",
          target_author: %{
            did: "did:plc:author",
            handle: "author.test",
            display_name: "Author"
          },
          post_text: "Which OTP boundary should own this failure?",
          selection_reason: "useful discussion scored 83",
          policy_score: 83,
          selected_at: "2026-10-05T11:00:00Z",
          budget: %{date: "2026-10-05", likes: 1, limit: 5, remaining: 4},
          review: %{state: "approved"}
        },
        %{
          event_key: "like:failed",
          event_state: "failed",
          proposal_status: "failed",
          publication_state: "failed",
          target_uri: "at://did:plc:other/town.delve.feed.post/target-two",
          target_author: %{did: "did:plc:other", display_name: "Other"},
          post_text: nil,
          selection_reason: "policy evaluation failed",
          policy_score: nil,
          selected_at: "2026-10-05T10:00:00Z",
          budget: %{},
          review: %{state: "pending"}
        }
      ])
      |> put_in([:drafts, :approved_count], 1)
      |> put_in([:drafts, :pending_count], 1)
      |> put_in([:drafts, :type_counts, :like], 2)

    html = render_dashboard(assigns)

    assert html =~ ~s(id="like-proposals")
    assert html =~ "Like proposals"
    assert html =~ "@author.test"
    assert html =~ "Which OTP boundary should own this failure?"
    assert html =~ "useful discussion scored 83"
    assert html =~ "Policy score:</strong> 83"
    assert html =~ "1 of 5 used · 4 left"
    assert html =~ "Oct 05 · 11:00 UTC"
    assert html =~ "View target post"
    assert html =~ "/profile/did%3Aplc%3Aauthor/post/target-one"
    assert html =~ "Publish like to DelveTown"
    assert html =~ ~s(phx-click="publish_simulated_like")
    assert html =~ ~s(phx-value-event_key="like:simulated")
    assert html =~ "Publish this exact approved like to DelveTown?"
    assert html =~ "Failed"
    assert html =~ "Target post text was not stored for this older proposal."
    refute html =~ ~s(phx-value-event_key="like:failed")
  end

  test "shows a durable published like state without another publish button" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :like_proposals], [
        %{
          event_key: "like:published",
          event_state: "completed",
          proposal_status: "simulated",
          publication_state: "published",
          target_uri: "at://did:plc:author/town.delve.feed.post/target-one",
          target_author: %{did: "did:plc:author", handle: "author.test"},
          post_text: "A durable target.",
          selection_reason: "useful discussion",
          selected_at: "2026-10-05T11:00:00Z",
          published_at: "2026-10-05T11:02:00Z",
          budget: %{}
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published"
    assert html =~ "View target post"
    refute html =~ "Publish like to DelveTown"
  end

  test "shows local image previews and a confirmed manual publish action" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :image_drafts], [
        %{
          draft_key: "agentjido:self-portrait",
          caption: "AgentJido at the workbench.",
          alt_text: "A green robot writing at a workbench.",
          validation_state: "valid",
          publication_state: "staged",
          inserted_at: "2026-10-05T12:04:00Z",
          post_uri: nil,
          review: %{state: "approved"},
          artifact: %{
            digest: "sha256:preview",
            preview_data_url: "data:image/png;base64,iVBORw0KGgo=",
            mime_type: "image/png",
            byte_size: 8,
            width: 1024,
            height: 1024,
            upload_state: "staged"
          }
        }
      ])
      |> put_in([:drafts, :approved_count], 1)
      |> put_in([:drafts, :type_counts, :image], 1)

    html = render_dashboard(assigns)

    assert html =~ ~s(<h1 id="page-title">Drafts &amp; approvals</h1>)
    assert html =~ ~s(id="drafts-tab" class="operator-nav-link active")
    assert html =~ ~s(id="drafts-panel")
    assert html =~ "Approval and rejection are local"
    assert html =~ "SQLite decisions"
    assert html =~ ~s(src="data:image/png;base64,iVBORw0KGgo=")
    assert html =~ ~s(alt="A green robot writing at a workbench.")
    assert html =~ "AgentJido at the workbench."
    assert html =~ "Validation"
    assert html =~ "Upload"
    assert html =~ "Publication"
    assert html =~ "1024×1024"
    assert html =~ ~s(phx-click="publish_image")
    assert html =~ ~s(phx-value-draft_key="agentjido:self-portrait")
    assert html =~ "Upload and publish this exact approved image"
  end

  test "shows a published image link instead of the publish button" do
    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :image_drafts], [
        %{
          draft_key: "image:published",
          caption: "Published image.",
          alt_text: "Published image preview.",
          validation_state: "valid",
          publication_state: "published",
          post_uri: "at://did:plc:agentjido/town.delve.feed.post/image-rkey",
          artifact: %{
            digest: "sha256:published",
            preview_data_url: "data:image/png;base64,iVBORw0KGgo=",
            mime_type: "image/png",
            byte_size: 8,
            width: nil,
            height: nil,
            upload_state: "uploaded"
          }
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published"
    assert html =~ "/profile/agentjido.test/post/image-rkey"
    refute html =~ "Publish image to DelveTown"
  end

  test "renders the fixed AgentJido self-portrait as its exact top-level draft" do
    definition = SelfPortraitDraft.definition()
    bytes = File.read!(definition.asset_path)
    preview_data_url = "data:image/png;base64,#{Base.encode64(bytes)}"

    assigns =
      base_assigns()
      |> Map.put(:active_tab, "drafts")
      |> Map.put(:manual_publish_enabled, true)
      |> put_in([:inspection, :image_drafts], [
        %{
          draft_key: definition.draft_key,
          caption: definition.caption,
          alt_text: definition.alt_text,
          validation_state: "valid",
          publication_state: "staged",
          review: %{state: "approved"},
          artifact: %{
            digest: definition.expected_digest,
            preview_data_url: preview_data_url,
            mime_type: definition.mime_type,
            byte_size: byte_size(bytes),
            width: definition.width,
            height: definition.height,
            upload_state: "staged"
          }
        }
      ])
      |> put_in([:drafts, :approved_count], 1)
      |> put_in([:drafts, :type_counts, :image], 1)

    html = render_dashboard(assigns)

    assert html =~ definition.draft_key
    assert html =~ definition.caption
    assert html =~ definition.alt_text
    assert html =~ definition.expected_digest
    assert html =~ "1024×1024"
    assert html =~ "data:image/png;base64,"
    assert html =~ "Image post"
    assert html =~ "Publish image to DelveTown"
  end

  test "shows when protocol writes are enabled" do
    assigns =
      base_assigns()
      |> put_in([:status, :writes_enabled?], true)
      |> Map.put(:operational_state, %{
        key: "active",
        label: "Writes enabled",
        effect: "Scheduled Agent work can create public protocol effects.",
        next: "Use the review path before any future one-click action."
      })

    html = render_dashboard(assigns)

    assert html =~ "Writes enabled"
    assert html =~ ~s(aria-checked="true")
    assert html =~ ">ON</strong>"
  end

  test "shows when dry-run actions advance local memory" do
    assigns =
      base_assigns()
      |> put_in([:status, :dry_run_mark_actioned?], true)
      |> Map.put(:operational_state, %{
        key: "safe",
        label: "Dry run: actions simulated",
        effect: "Protocol effects are blocked. Selected actions advance local dry-run memory.",
        next: "A simulated action is not published and will not run again."
      })

    html = render_dashboard(assigns)

    assert html =~ "Dry run: actions simulated"
    assert html =~ "Selected actions advance local dry-run memory"
    assert html =~ "A simulated action is not published"
    assert html =~ ">OFF</strong>"
  end

  test "links the latest published reply from the audit event" do
    assigns =
      base_assigns()
      |> update_in([:last_run], &Map.delete(&1, :record_uri))
      |> Map.put(:workflow_events, [
        %{
          type: :published_reply,
          at: "2026-10-05T14:05:13Z",
          data: %{
            record_uri: "at://did:plc:agentjido/town.delve.feed.post/audited-reply"
          }
        }
      ])

    html = render_dashboard(assigns)

    assert html =~ "Published reply"
    assert html =~ "audited-reply"
  end

  defp render_dashboard(assigns \\ base_assigns()) do
    assigns
    |> DashboardLive.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp base_assigns do
    %{
      active_tab: "overview",
      theme: "system",
      show_setup: false,
      setup: setup_status(false),
      setup_notice: nil,
      status: %{
        writes_enabled?: false,
        schedule_enabled?: true,
        cron: "*/15 * * * *",
        session: %{connected?: true, handle: "agentjido.test"}
      },
      status_error: nil,
      budget: %{replies: 1, posts: 0},
      decision: %{
        action: "reply",
        reason: "The thread asks a direct technical question.",
        topic: "OTP",
        text: "A supervisor gives this failure boundary one owner."
      },
      last_cycle: %{
        intent: "answer_direct_request",
        kind: "reactive",
        status: "proposed",
        candidate_id: "at://did:plc:a5uoyxqts4y3iwo2dk74ygma/town.delve.feed.post/3mx4w2xzwzjzs"
      },
      last_run: %{
        summary: "One reply proposed",
        selection: %{score: 138, reason: "direct scored 138"},
        record_uri: "at://did:plc:agentjido/town.delve.feed.post/published-reply"
      },
      workflow_events: [
        %{
          type: "cycle.proposed",
          at: "2026-10-05T12:00:00Z",
          data: %{action: "reply", record_uri: nil}
        }
      ],
      agent_events: [],
      inspection: %{
        simulated_posts: [],
        like_proposals: [],
        image_drafts: [],
        events: %{
          counts: %{
            "pending" => 1,
            "claimed" => 0,
            "completed" => 4,
            "ignored" => 2,
            "failed" => 0
          }
        },
        actors: %{
          recent: [
            %{
              did: "did:plc:member",
              handle: "member.test",
              display_name: "Member",
              last_interaction_at: "2026-10-05T11:58:00Z",
              contact_count: 2,
              welcome_status: "completed",
              opted_out?: false
            }
          ]
        },
        conversations: %{counts: %{"active" => 1, "closed" => 0}},
        scans: [
          %{
            name: "notifications",
            cursor: "cursor-2",
            lease_active?: false,
            last_completed_at: "2026-10-05T11:59:00Z"
          }
        ],
        effects: %{
          counts: %{
            "reserved" => 0,
            "uncertain" => 1,
            "completed" => 3,
            "permanent_failure" => 0
          },
          reconciled: 1,
          attention: [
            %{
              operation_key: "reply:pending",
              kind: "reply",
              status: "uncertain",
              attempt_count: 1
            }
          ],
          completed_receipts: [
            %{
              operation_key: "reply:complete",
              rkey: "reply-rkey",
              completed_at: "2026-10-05T11:57:00Z",
              receipt: %{uri: "at://receipt", cid: "bafy"}
            }
          ]
        },
        sqlite: %{
          migrations: %{
            status: "current",
            applied: ["20261005000000", "20261005000001", "20261005000002"],
            pending: []
          },
          legacy_imports: [
            %{
              name: "dets-and-file-v1",
              status: "complete",
              counts: %{"effects" => 3, "events" => 2, "checkpoints" => 1}
            }
          ]
        }
      },
      inspection_error: nil,
      reactive_review: review_feedback(:idle),
      proactive_review: review_feedback(:idle),
      manual_publish_enabled: false,
      publish_notice: nil,
      like_publish_notice: nil,
      image_publish_notice: nil,
      draft_review_notice: nil,
      settings_notice: nil,
      character: %{
        name: "AgentJido",
        mission: "Make BEAM agent engineering easier to understand.",
        traits: ["calm", "exact"],
        topical_scope: ["BEAM and OTP", "agent architecture"]
      },
      disclosure: %{operator: %{contact: "https://mike-hostetler.com"}},
      port: 4040,
      refreshed_at: "2026-10-05T12:00:00Z",
      refreshed_label: "12:00:00 UTC",
      overview: overview_assigns(),
      inbox: inbox_assigns(),
      drafts: %{
        total_count: 0,
        pending_count: 0,
        approved_count: 0,
        rejected_count: 0,
        published_count: 0,
        type_counts: %{text: 0, like: 0, image: 0}
      },
      settings_editor: settings_assigns(),
      operational_state: %{
        key: "safe",
        label: "Safe: writes off",
        effect: "Protocol effects are blocked. Review cycles can inspect and propose.",
        next: nil
      }
    }
  end

  defp settings_assigns do
    %{
      available?: true,
      version: 3,
      schema_version: 2,
      activation_guide: [],
      sections: [
        settings_section("connection", "Connection", [
          settings_field(:account_app_password, "App password", :password,
            value: "",
            activation_label: "After reconnect",
            secret_stored?: true
          )
        ]),
        settings_section("behavior", "Behavior", [
          settings_field(:enabled_actions, "Enabled actions", :checkboxes,
            selected: ["reply", "like"],
            options: [
              %{value: "reply", label: "Reply"},
              %{value: "like", label: "Like"}
            ]
          )
        ]),
        settings_section("limits", "Limits", [
          settings_field(:daily_reply_limit, "Daily reply limit", :number,
            value: 3,
            min: 0,
            max: 100
          )
        ]),
        settings_section("schedules", "Schedules", [
          settings_field(:reactive_review_cron, "Reactive review cron", :cron,
            value: "*/15 * * * *",
            activation_label: "After worker sync"
          )
        ]),
        settings_section("safety", "Safety", [
          settings_field(:autonomy_mode, "Autonomy mode", :select,
            value: "observe",
            options: [
              %{value: "observe", label: "Observe only"},
              %{value: "autonomous", label: "Autonomous"}
            ]
          ),
          settings_field(:manual_publish_enabled, "Allow manual publish", :checkbox,
            checked?: false
          )
        ]),
        settings_section("console", "Console", [
          settings_field(:dashboard_port, "Dashboard port", :number,
            value: 4040,
            min: 1,
            max: 65_535,
            activation_label: "After restart"
          )
        ])
      ],
      history: [
        %{
          version: 3,
          current?: true,
          source: "Operator save",
          inserted_at: "2026-10-06T14:00:00Z",
          inserted_label: "Oct 06 · 14:00 UTC",
          changed: ["Daily reply limit"],
          confirms_autonomous?: false,
          confirms_notifications?: false
        },
        %{
          version: 2,
          current?: false,
          source: "Initial setup",
          inserted_at: "2026-10-06T13:00:00Z",
          inserted_label: "Oct 06 · 13:00 UTC",
          changed: ["Account identifier"],
          confirms_autonomous?: false,
          confirms_notifications?: false
        }
      ]
    }
  end

  defp settings_section(key, label, fields) do
    %{key: key, label: label, description: "#{label} settings.", fields: fields}
  end

  defp settings_field(key, label, input, opts) do
    name = Atom.to_string(key)

    %{
      key: key,
      name: name,
      id: "setting-#{String.replace(name, "_", "-")}",
      label: label,
      input: input,
      value: Keyword.get(opts, :value),
      checked?: Keyword.get(opts, :checked?, false),
      selected: Keyword.get(opts, :selected, []),
      options: Keyword.get(opts, :options, []),
      activation_label: Keyword.get(opts, :activation_label, "Next cycle"),
      validation: Keyword.get(opts, :validation),
      help: Keyword.get(opts, :help, "Activation details."),
      secret_stored?: Keyword.get(opts, :secret_stored?, false),
      min: Keyword.get(opts, :min),
      max: Keyword.get(opts, :max)
    }
  end

  defp overview_assigns do
    %{
      autonomy: %{
        mode: "observe",
        label: "Observe",
        state: "safe",
        detail: "Collect activity and prepare local proposals. Protocol writes stay off."
      },
      connection: %{
        connected?: true,
        label: "Connected",
        state: "healthy",
        detail: "Signed in as @agentjido.test."
      },
      attention: [
        %{
          key: "effects",
          label: "1 effect needs reconciliation",
          detail: "Inspect reserved, uncertain, or failed effects before another write.",
          state: "attention"
        }
      ],
      schedule: %{
        enabled?: true,
        items: [
          %{
            key: "reactive",
            label: "Inbox review",
            cron: "*/15 * * * *",
            next_at_iso8601: "2026-10-05T12:15:00Z",
            relative: "in 15 min"
          }
        ]
      },
      budgets: [
        %{
          key: "replies",
          label: "Replies and reposts",
          used: 1,
          limit: 3,
          remaining: 2,
          percent: 33
        },
        %{key: "posts", label: "Posts", used: 0, limit: 1, remaining: 1, percent: 0},
        %{key: "welcomes", label: "Welcomes", used: 0, limit: 2, remaining: 2, percent: 0},
        %{key: "follows", label: "Follows", used: 0, limit: 5, remaining: 5, percent: 0},
        %{key: "likes", label: "Likes", used: 0, limit: 5, remaining: 5, percent: 0}
      ],
      recent_actions: [
        %{
          type: "decision",
          label: "Reply",
          status: "proposed",
          detail: "Direct technical question",
          at: "2026-10-05T12:00:00Z"
        }
      ]
    }
  end

  defp inbox_assigns do
    %{
      actionable_count: 1,
      proposal_count: 1,
      categories: [
        %{key: "reply", label: "Replies", count: 1},
        %{key: "mention", label: "Mentions", count: 0},
        %{key: "follow", label: "Follows", count: 0},
        %{key: "like", label: "Likes", count: 0}
      ],
      last_scan: %{
        name: "notifications",
        last_completed_at: "2026-10-05T11:59:00Z",
        lease_active?: false
      },
      events: [
        %{
          event_key: "reply:1",
          kind: "reply",
          state: "pending",
          actor: %{did: "did:plc:member", handle: "member.test", display_name: "Member"},
          record_uri: "at://did:plc:member/town.delve.feed.post/source-post",
          occurred_at: "2026-10-05T11:58:00Z",
          claimed_at: nil,
          terminal_at: nil,
          updated_at: "2026-10-05T11:58:00Z",
          proposal: %{
            action: "reply",
            status: "proposed",
            text: "A supervisor gives this failure boundary one owner.",
            reason: "The thread asks a direct technical question."
          }
        }
      ]
    }
  end

  defp review_feedback(:idle) do
    %{
      status: :idle,
      label: "Ready for review",
      detail: "Queue one review with the current dry-run settings.",
      disabled?: false,
      job_id: nil
    }
  end

  defp review_feedback(:queued) do
    %{
      status: :queued,
      label: "Review queued",
      detail: "The review will run through the normal scan lease.",
      disabled?: true,
      job_id: 11
    }
  end

  defp review_feedback(:running) do
    %{
      status: :running,
      label: "Review running",
      detail: "The worker is reviewing the timeline.",
      disabled?: true,
      job_id: 11
    }
  end

  defp review_feedback(:completed) do
    %{
      status: :completed,
      label: "Review completed",
      detail: "The dashboard now includes saved proposals.",
      disabled?: false,
      job_id: 11
    }
  end

  defp review_feedback(:skipped) do
    %{
      status: :skipped,
      label: "Review already queued",
      detail: "No duplicate job was created.",
      disabled?: true,
      job_id: 11
    }
  end

  defp review_feedback(:failed) do
    %{
      status: :failed,
      label: "Review failed",
      detail: "The worker failed and Oban will retry it.",
      disabled?: true,
      job_id: 11
    }
  end

  defp setup_status(required?, opts \\ []) do
    password_configured? = Keyword.get(opts, :password_configured?, not required?)

    %{
      available?: true,
      required?: required?,
      identifier: if(required?, do: "", else: "agent.test"),
      password_configured?: password_configured?,
      decision_model: "openai:gpt-4o-mini",
      model_options: [
        %{value: "openai:gpt-4o-mini", label: "OpenAI GPT-4o mini"},
        %{value: "openai:gpt-5-mini", label: "OpenAI GPT-5 mini"}
      ],
      autonomy_mode: "observe",
      autonomy_options: [
        %{value: "observe", label: "Observe only"},
        %{value: "review", label: "Review before action"}
      ],
      llm_key: %{
        provider: "OpenAI",
        environment: "OPENAI_API_KEY",
        configured?: Keyword.get(opts, :llm_key_configured?, true)
      },
      settings_version: 1
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_delvetown, key)
  defp restore_env(key, value), do: Application.put_env(:jido_delvetown, key, value)
end
