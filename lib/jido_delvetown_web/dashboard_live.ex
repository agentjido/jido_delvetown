defmodule JidoDelvetownWeb.DashboardLive do
  @moduledoc false

  use Phoenix.LiveView

  alias JidoDelvetown.{ManualPublisher, Personality}

  @refresh_ms 3_000

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    assigns =
      snapshot()
      |> Map.put(:active_tab, active_tab(params))
      |> Map.put(:publish_notice, nil)

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign(socket, snapshot())}
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
     |> assign(snapshot())
     |> assign(:active_tab, "simulated-posts")
     |> assign(:publish_notice, notice)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard-shell">
      <style>
        :root {
          color-scheme: dark;
          --canvas: #07110f;
          --surface: #0d1916;
          --surface-raised: #12211d;
          --line: #263b35;
          --line-strong: #3c5a51;
          --text: #edf7f2;
          --muted: #9bb0a8;
          --quiet: #7f958d;
          --green: #75e6a8;
          --green-deep: #133c2a;
          --cyan: #78d8e9;
          --cyan-deep: #12343b;
          --amber: #ffcb6b;
          --amber-deep: #44331a;
          --red: #ff948f;
          --red-deep: #451f20;
          --radius: 14px;
        }

        * { box-sizing: border-box; }

        body {
          margin: 0;
          background:
            radial-gradient(circle at 88% 0%, rgba(38, 112, 83, 0.16), transparent 30rem),
            var(--canvas);
          color: var(--text);
          font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 15px;
          line-height: 1.5;
        }

        button, summary, a { font: inherit; }

        a { color: var(--cyan); }

        :focus-visible {
          outline: 3px solid var(--cyan);
          outline-offset: 3px;
        }

        .dashboard-shell {
          width: min(1180px, calc(100% - 32px));
          margin: 0 auto;
          padding: 28px 0 44px;
        }

        .page-header {
          display: flex;
          align-items: end;
          justify-content: space-between;
          gap: 24px;
          margin-bottom: 18px;
        }

        .eyebrow,
        .panel-kicker,
        .metric-label,
        .switch-label {
          margin: 0;
          color: var(--green);
          font-size: 12px;
          font-weight: 760;
          letter-spacing: 0.12em;
          text-transform: uppercase;
        }

        h1, h2, h3, p { margin-top: 0; }

        h1 {
          margin-bottom: 0;
          font-size: clamp(25px, 4vw, 32px);
          line-height: 1.08;
          letter-spacing: -0.035em;
        }

        h2 {
          margin-bottom: 14px;
          font-size: 18px;
          line-height: 1.25;
          letter-spacing: -0.015em;
        }

        h3 {
          margin-bottom: 8px;
          font-size: 14px;
        }

        .refresh-note {
          margin: 0;
          color: var(--muted);
          font-size: 13px;
          text-align: right;
          white-space: nowrap;
        }

        .refresh-note time { color: var(--text); }

        .state-rail {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(270px, 360px);
          align-items: stretch;
          gap: 18px;
          margin-bottom: 12px;
          padding: 20px;
          border: 1px solid var(--line-strong);
          border-radius: calc(var(--radius) + 4px);
          background: linear-gradient(135deg, rgba(117, 230, 168, 0.08), rgba(13, 25, 22, 0.96) 55%);
        }

        .state-rail.state-attention {
          border-color: rgba(255, 148, 143, 0.58);
          background: linear-gradient(135deg, rgba(255, 148, 143, 0.11), rgba(13, 25, 22, 0.96) 55%);
        }

        .state-rail.state-active {
          border-color: rgba(255, 203, 107, 0.65);
          background: linear-gradient(135deg, rgba(255, 203, 107, 0.1), rgba(13, 25, 22, 0.96) 55%);
        }

        .state-title-row {
          display: flex;
          align-items: center;
          gap: 10px;
          margin-bottom: 8px;
        }

        .state-dot {
          width: 11px;
          height: 11px;
          flex: 0 0 auto;
          border-radius: 50%;
          background: var(--green);
          box-shadow: 0 0 0 5px rgba(117, 230, 168, 0.12);
        }

        .state-attention .state-dot {
          background: var(--red);
          box-shadow: 0 0 0 5px rgba(255, 148, 143, 0.12);
        }

        .state-active .state-dot {
          background: var(--amber);
          box-shadow: 0 0 0 5px rgba(255, 203, 107, 0.12);
        }

        .state-title {
          margin: 0;
          font-size: clamp(22px, 3.2vw, 30px);
          line-height: 1.1;
          letter-spacing: -0.03em;
        }

        .state-effect {
          max-width: 65ch;
          margin-bottom: 4px;
          color: var(--text);
          font-size: 15px;
        }

        .state-next {
          margin-bottom: 0;
          color: var(--muted);
          font-size: 14px;
        }

        .technical-details {
          margin-top: 12px;
          color: var(--muted);
          font-size: 13px;
        }

        .technical-details summary,
        .about-panel summary {
          width: fit-content;
          cursor: pointer;
          color: var(--cyan);
          font-weight: 680;
        }

        .technical-details pre {
          overflow-wrap: anywhere;
          white-space: pre-wrap;
          color: var(--red);
          font-size: 12px;
        }

        .write-switch {
          display: flex;
          align-items: center;
          gap: 15px;
          width: 100%;
          min-height: 108px;
          padding: 18px;
          border: 1px solid rgba(117, 230, 168, 0.42);
          border-radius: var(--radius);
          background: rgba(7, 17, 15, 0.72);
          color: var(--text);
          text-align: left;
          opacity: 1;
        }

        .write-switch.on {
          border-color: rgba(255, 203, 107, 0.72);
          background: rgba(68, 51, 26, 0.54);
        }

        .switch-track {
          position: relative;
          display: inline-block;
          width: 68px;
          height: 38px;
          flex: 0 0 68px;
          border: 1px solid #527066;
          border-radius: 99px;
          background: #1a2b26;
        }

        .switch-thumb {
          position: absolute;
          top: 4px;
          left: 4px;
          width: 28px;
          height: 28px;
          border-radius: 50%;
          background: var(--muted);
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
          transition: transform 160ms ease;
        }

        .write-switch.on .switch-track {
          border-color: var(--amber);
          background: var(--amber-deep);
        }

        .write-switch.on .switch-thumb {
          background: var(--amber);
          transform: translateX(30px);
        }

        .switch-copy { display: grid; gap: 1px; }
        .switch-copy strong { font-size: 19px; letter-spacing: 0.02em; }
        .switch-copy small { color: var(--muted); font-size: 12px; }
        .write-switch.on .switch-label { color: var(--amber); }

        .status-strip {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          margin-bottom: 16px;
          border: 1px solid var(--line);
          border-radius: var(--radius);
          background: var(--surface);
        }

        .delve-links {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 8px;
          margin-bottom: 16px;
          padding: 10px 12px;
          border: 1px solid var(--line);
          border-radius: 11px;
          background: rgba(13, 25, 22, 0.72);
        }

        .delve-links > span {
          margin-right: 4px;
          color: var(--muted);
          font-size: 12px;
          font-weight: 760;
          letter-spacing: 0.08em;
          text-transform: uppercase;
        }

        .delve-links a {
          min-height: 34px;
          padding: 6px 10px;
          border: 1px solid var(--line-strong);
          border-radius: 8px;
          background: var(--surface-raised);
          color: var(--cyan);
          font-size: 13px;
          font-weight: 680;
          text-decoration: none;
        }

        .delve-links a:hover { border-color: var(--cyan); }

        .dashboard-tabs {
          display: flex;
          gap: 7px;
          margin-bottom: 16px;
          padding: 5px;
          border: 1px solid var(--line);
          border-radius: 12px;
          background: var(--surface);
        }

        .dashboard-tab {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          min-height: 40px;
          padding: 8px 13px;
          border: 1px solid transparent;
          border-radius: 8px;
          color: var(--muted);
          font-size: 13px;
          font-weight: 720;
          text-decoration: none;
        }

        .dashboard-tab:hover {
          border-color: var(--line-strong);
          color: var(--text);
        }

        .dashboard-tab.active {
          border-color: rgba(117, 230, 168, 0.4);
          background: var(--green-deep);
          color: var(--green);
        }

        .tab-count {
          min-width: 22px;
          padding: 1px 7px;
          border-radius: 99px;
          background: rgba(7, 17, 15, 0.68);
          color: currentColor;
          font-size: 11px;
          text-align: center;
        }

        .status-item {
          min-width: 0;
          padding: 14px 16px;
          border-right: 1px solid var(--line);
        }

        .status-item:last-child { border-right: 0; }

        .status-heading {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 10px;
          margin-bottom: 4px;
        }

        .status-heading span:first-child {
          color: var(--muted);
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
        }

        .status-value {
          overflow: hidden;
          margin: 0;
          color: var(--text);
          font-size: 14px;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .status-detail {
          margin: 0;
          color: var(--quiet);
          font-size: 12px;
        }

        .badge {
          display: inline-flex;
          align-items: center;
          min-height: 23px;
          padding: 2px 8px;
          border-radius: 99px;
          font-size: 11px;
          font-weight: 760;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          white-space: nowrap;
        }

        .badge.healthy, .badge.safe { background: var(--green-deep); color: var(--green); }
        .badge.idle { background: var(--cyan-deep); color: var(--cyan); }
        .badge.attention { background: var(--red-deep); color: var(--red); }
        .badge.active { background: var(--amber-deep); color: var(--amber); }

        .primary-grid,
        .health-grid,
        .event-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 16px;
          margin-bottom: 16px;
        }

        .panel {
          min-width: 0;
          padding: 18px;
          border: 1px solid var(--line);
          border-radius: var(--radius);
          background: rgba(13, 25, 22, 0.9);
        }

        .panel-header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 12px;
          margin-bottom: 14px;
        }

        .panel-header h2 { margin-bottom: 0; }

        .count {
          color: var(--muted);
          font-size: 12px;
          white-space: nowrap;
        }

        .proposal-action {
          margin-bottom: 8px;
          color: var(--green);
          font-size: 21px;
          font-weight: 760;
          overflow-wrap: anywhere;
        }

        .proposal-copy {
          margin-bottom: 14px;
          color: var(--text);
          font-size: 15px;
        }

        .proposal-text {
          margin: 0;
          padding: 13px 14px;
          border-left: 3px solid var(--green);
          border-radius: 0 8px 8px 0;
          background: rgba(117, 230, 168, 0.06);
          color: #dceae4;
          font-size: 14px;
        }

        .detail-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 14px;
        }

        .metric {
          min-width: 0;
          padding-bottom: 10px;
          border-bottom: 1px solid var(--line);
        }

        .metric-value {
          margin: 3px 0 0;
          color: var(--text);
          font-size: 14px;
          overflow-wrap: anywhere;
        }

        .budget-row {
          display: flex;
          gap: 10px;
          margin-bottom: 14px;
        }

        .budget-number {
          flex: 1;
          padding: 13px;
          border: 1px solid var(--line);
          border-radius: 10px;
          background: var(--surface-raised);
        }

        .budget-number strong {
          display: block;
          font-size: 25px;
          line-height: 1;
        }

        .budget-number span { color: var(--muted); font-size: 12px; }

        .health-counts {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: 8px;
          margin-bottom: 16px;
        }

        .health-count {
          min-width: 0;
          padding: 10px;
          border: 1px solid var(--line);
          border-radius: 9px;
          background: var(--surface-raised);
        }

        .health-count strong {
          display: block;
          font-size: 20px;
          line-height: 1.1;
        }

        .health-count span {
          color: var(--muted);
          font-size: 11px;
          overflow-wrap: anywhere;
        }

        .subsection-title {
          margin: 16px 0 8px;
          color: var(--muted);
          font-size: 12px;
          font-weight: 760;
          letter-spacing: 0.07em;
          text-transform: uppercase;
        }

        .event-list {
          display: grid;
          gap: 8px;
          margin: 0;
          padding: 0;
          list-style: none;
        }

        .event-item {
          padding: 11px 12px;
          border: 1px solid var(--line);
          border-radius: 9px;
          background: rgba(18, 33, 29, 0.72);
        }

        .event-title {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 12px;
          margin-bottom: 4px;
        }

        .event-title strong {
          min-width: 0;
          color: var(--cyan);
          font-size: 13px;
          overflow-wrap: anywhere;
        }

        .event-title time {
          flex: 0 0 auto;
          color: var(--quiet);
          font-size: 12px;
        }

        .event-data {
          margin: 0;
          color: var(--muted);
          font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
          font-size: 12px;
          overflow-wrap: anywhere;
        }

        .empty {
          margin: 0;
          padding: 12px;
          border: 1px dashed var(--line-strong);
          border-radius: 9px;
          color: var(--muted);
          font-size: 14px;
        }

        .simulated-panel { margin-bottom: 18px; }

        .simulated-intro {
          max-width: 72ch;
          margin-bottom: 18px;
          color: var(--muted);
        }

        .simulated-list {
          display: grid;
          gap: 12px;
          margin: 0;
          padding: 0;
          list-style: none;
        }

        .simulated-card {
          padding: 16px;
          border: 1px solid var(--line);
          border-radius: 11px;
          background: var(--surface-raised);
        }

        .simulated-card-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          margin-bottom: 11px;
        }

        .simulated-card-header time {
          color: var(--quiet);
          font-size: 12px;
        }

        .simulated-draft {
          margin: 0 0 13px;
          padding: 14px 15px;
          border-left: 3px solid var(--cyan);
          border-radius: 0 8px 8px 0;
          background: rgba(120, 216, 233, 0.06);
          color: var(--text);
          font-size: 15px;
          white-space: pre-wrap;
        }

        .simulated-meta {
          display: flex;
          flex-wrap: wrap;
          gap: 6px 14px;
          margin-bottom: 10px;
          color: var(--muted);
          font-size: 12px;
        }

        .simulated-meta strong { color: var(--text); font-weight: 650; }

        .publish-notice {
          margin-bottom: 14px;
          padding: 11px 13px;
          border: 1px solid rgba(117, 230, 168, 0.48);
          border-radius: 9px;
          background: rgba(19, 60, 42, 0.5);
          color: var(--text);
        }

        .publish-notice.attention {
          border-color: rgba(255, 148, 143, 0.55);
          background: rgba(69, 31, 32, 0.48);
        }

        .simulated-actions {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 9px 14px;
        }

        .source-link {
          color: var(--cyan);
          font-size: 12px;
          font-weight: 680;
          text-decoration: none;
        }

        .source-link:hover { text-decoration: underline; }

        .publish-button {
          min-height: 38px;
          margin-left: auto;
          padding: 8px 13px;
          border: 1px solid rgba(117, 230, 168, 0.65);
          border-radius: 9px;
          background: var(--green-deep);
          color: var(--text);
          cursor: pointer;
          font-size: 13px;
          font-weight: 720;
        }

        .publish-button:hover { border-color: var(--green); }

        .publish-button:disabled {
          border-color: var(--line);
          background: #14231f;
          color: var(--quiet);
          cursor: not-allowed;
        }

        .published-state {
          margin-left: auto;
          color: var(--green);
          font-size: 12px;
          font-weight: 680;
        }

        .planned-controls {
          display: grid;
          grid-template-columns: minmax(210px, 1fr) minmax(0, 2fr);
          align-items: center;
          gap: 20px;
          margin-bottom: 16px;
          padding: 15px 18px;
          border: 1px solid var(--line);
          border-radius: var(--radius);
          background: var(--surface);
        }

        .planned-controls h2 { margin-bottom: 3px; }
        .planned-controls p { margin-bottom: 0; color: var(--muted); font-size: 13px; }

        .control-row {
          display: flex;
          justify-content: flex-end;
          gap: 8px;
        }

        .control-row button {
          min-height: 44px;
          padding: 9px 13px;
          border: 1px solid var(--line-strong);
          border-radius: 9px;
          background: #14231f;
          color: #8fa29b;
          cursor: not-allowed;
          font-size: 13px;
          opacity: 1;
        }

        .about-panel {
          margin-bottom: 18px;
          padding: 16px 18px;
          border: 1px solid var(--line);
          border-radius: var(--radius);
          background: var(--surface);
        }

        .about-panel summary { font-size: 15px; }

        .about-content {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 18px;
          padding-top: 16px;
        }

        .about-content p, .about-content li { color: var(--muted); font-size: 14px; }
        .about-content ul { margin: 0; padding-left: 19px; }

        .tag-list {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
          margin-bottom: 15px;
        }

        .tag {
          padding: 3px 8px;
          border: 1px solid var(--line);
          border-radius: 99px;
          color: var(--muted);
          font-size: 12px;
        }

        .footer-note {
          margin: 0;
          color: var(--muted);
          font-size: 13px;
          text-align: center;
        }

        @media (max-width: 820px) {
          .dashboard-shell { width: min(100% - 24px, 680px); padding-top: 20px; }
          .page-header { align-items: start; flex-direction: column; gap: 8px; }
          .refresh-note { text-align: left; }
          .state-rail { grid-template-columns: 1fr; }
          .status-strip, .primary-grid, .health-grid, .event-grid, .about-content { grid-template-columns: 1fr; }
          .status-item { border-right: 0; border-bottom: 1px solid var(--line); }
          .status-item:last-child { border-bottom: 0; }
          .planned-controls { grid-template-columns: 1fr; }
          .control-row { justify-content: start; flex-wrap: wrap; }
        }

        @media (max-width: 520px) {
          .dashboard-shell { width: min(100% - 20px, 480px); }
          .state-rail, .panel { padding: 15px; }
          .write-switch { min-height: 96px; padding: 14px; }
          .switch-track { width: 60px; flex-basis: 60px; }
          .write-switch.on .switch-thumb { transform: translateX(22px); }
          .detail-grid { grid-template-columns: 1fr; gap: 9px; }
          .health-counts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
          .event-title { align-items: start; flex-direction: column; gap: 2px; }
          .control-row { display: grid; grid-template-columns: 1fr; }
          .control-row button { width: 100%; }
        }

        @media (prefers-reduced-motion: reduce) {
          *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; }
        }
      </style>

      <header class="page-header">
        <div>
          <p class="eyebrow">Local agent control</p>
          <h1>AgentJido / DelveTown</h1>
        </div>
        <p class="refresh-note">
          Last refresh <time datetime={@refreshed_at}>{@refreshed_label}</time> · every 3s
        </p>
      </header>

      <section class={"state-rail state-#{@operational_state.key}"} aria-live="polite">
        <div>
          <p class="panel-kicker">Operational state</p>
          <div class="state-title-row">
            <span class="state-dot" aria-hidden="true"></span>
            <h2 class="state-title">{@operational_state.label}</h2>
          </div>
          <p class="state-effect">{@operational_state.effect}</p>
          <p :if={@operational_state.next} class="state-next">
            Next: {@operational_state.next}
          </p>
          <details :if={@status_error} class="technical-details">
            <summary>Technical details</summary>
            <pre>{@status_error}</pre>
          </details>
        </div>

        <button
          type="button"
          role="switch"
          aria-checked={to_string(map_value(@status, :writes_enabled?, false))}
          aria-label={write_switch_label(@status)}
          class={"write-switch #{write_switch_class(@status)}"}
          disabled
        >
          <span class="switch-track" aria-hidden="true">
            <span class="switch-thumb"></span>
          </span>
          <span class="switch-copy">
            <span class="switch-label">Protocol writes</span>
            <strong>{if map_value(@status, :writes_enabled?, false),
              do: "WRITES ON",
              else: "WRITES OFF"}</strong>
            <small>Status only · set in .env</small>
          </span>
        </button>
      </section>

      <section class="status-strip" aria-label="Agent status">
        <div class="status-item">
          <div class="status-heading">
            <span>Agent runtime</span>
            <span class={"badge #{runtime_class(@status_error)}"}>{runtime_label(@status_error)}</span>
          </div>
          <p class="status-value">{runtime_detail(@status_error)}</p>
          <p class="status-detail">Jido AgentServer</p>
        </div>

        <div class="status-item">
          <div class="status-heading">
            <span>DelveTown session</span>
            <span class={"badge #{session_class(@status)}"}>{session_name(@status)}</span>
          </div>
          <p class="status-value">{session_detail(@status)}</p>
          <p class="status-detail">Authenticated protocol client</p>
        </div>

        <div class="status-item">
          <div class="status-heading">
            <span>Reactive schedule</span>
            <span class={"badge #{schedule_class(@status)}"}>{schedule_label(@status)}</span>
          </div>
          <p class="status-value">{schedule_detail(@status)}</p>
          <p class="status-detail">Review cycle</p>
        </div>
      </section>

      <nav class="delve-links" aria-label="Open AgentJido in DelveTown">
        <span>Open in DelveTown</span>
        <a href="https://delve.town/" target="_blank" rel="noreferrer">Town feed ↗</a>
        <a
          :if={profile_url(@status)}
          href={profile_url(@status)}
          target="_blank"
          rel="noreferrer"
        >
          AgentJido profile ↗
        </a>
        <a
          :if={post_url(map_value(@last_cycle, :candidate_id))}
          href={post_url(map_value(@last_cycle, :candidate_id))}
          target="_blank"
          rel="noreferrer"
        >
          Proposed thread ↗
        </a>
        <a
          :if={post_url(published_uri(@last_run, @workflow_events), session_actor(@status))}
          href={post_url(published_uri(@last_run, @workflow_events), session_actor(@status))}
          target="_blank"
          rel="noreferrer"
        >
          Published reply ↗
        </a>
      </nav>

      <nav class="dashboard-tabs" role="tablist" aria-label="Dashboard views">
        <a
          id="overview-tab"
          class={"dashboard-tab #{tab_class(@active_tab, "overview")}"}
          href="/"
          role="tab"
          aria-selected={to_string(@active_tab == "overview")}
          aria-controls="overview-panel"
        >
          Overview
        </a>
        <a
          id="simulated-posts-tab"
          class={"dashboard-tab #{tab_class(@active_tab, "simulated-posts")}"}
          href="/?tab=simulated-posts"
          role="tab"
          aria-selected={to_string(@active_tab == "simulated-posts")}
          aria-controls="simulated-posts-panel"
        >
          Simulated posts
          <span class="tab-count">{length(inspection_list(@inspection, [:simulated_posts]))}</span>
        </a>
      </nav>

      <section
        :if={@active_tab == "overview"}
        id="overview-panel"
        class="primary-grid"
        role="tabpanel"
        aria-labelledby="overview-tab"
      >
        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">Imp decision</p>
              <h2>Participation proposal</h2>
            </div>
            <span class="badge idle">Proposal only</span>
          </div>

          <p class="proposal-action">{display(map_value(@decision, :action))}</p>
          <p class="proposal-copy">{display(map_value(@decision, :reason))}</p>
          <blockquote class="proposal-text">{display(map_value(@decision, :text))}</blockquote>
        </article>

        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">Bounded state</p>
              <h2>Cycle ledger</h2>
            </div>
          </div>

          <div class="budget-row" aria-label="Participation budget">
            <div class="budget-number">
              <strong>{display(map_value(@budget, :replies, 0))}</strong>
              <span>replies used</span>
            </div>
            <div class="budget-number">
              <strong>{display(map_value(@budget, :posts, 0))}</strong>
              <span>posts used</span>
            </div>
          </div>

          <div class="detail-grid">
            <div class="metric">
              <p class="metric-label">Intent</p>
              <p class="metric-value">{display(map_value(@last_cycle, :intent))}</p>
            </div>
            <div class="metric">
              <p class="metric-label">Cycle type</p>
              <p class="metric-value">{display(map_value(@last_cycle, :kind))}</p>
            </div>
            <div class="metric">
              <p class="metric-label">Status</p>
              <p class="metric-value">{display(map_value(@last_cycle, :status))}</p>
            </div>
            <div class="metric">
              <p class="metric-label">Candidate</p>
              <p class="metric-value">{display(map_value(@last_cycle, :candidate_id))}</p>
            </div>
            <div class="metric">
              <p class="metric-label">Policy score</p>
              <p class="metric-value">
                {display(map_value(map_value(@last_run, :selection, %{}), :score))}
              </p>
            </div>
            <div class="metric">
              <p class="metric-label">Selection reason</p>
              <p class="metric-value">
                {display(map_value(map_value(@last_run, :selection, %{}), :reason))}
              </p>
            </div>
          </div>

          <p class="state-next" style="margin-top: 13px;">
            {display(map_value(@last_run, :summary))}
          </p>
        </article>
      </section>

      <section
        :if={@active_tab == "overview"}
        class="health-grid"
        aria-label="Durable memory and effect health"
      >
        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">SQLite memory</p>
              <h2>Interaction memory</h2>
            </div>
            <span class="badge safe">Read only</span>
          </div>

          <div class="health-counts" aria-label="Event counts by state">
            <div :for={state <- event_states()} class="health-count">
              <strong>{inspection_count(@inspection, [:events, :counts], state)}</strong>
              <span>{state_label(state)} events</span>
            </div>
            <div class="health-count">
              <strong>{inspection_count(@inspection, [:conversations, :counts], "active")}</strong>
              <span>active conversations</span>
            </div>
          </div>

          <h3 class="subsection-title">Recent actor contact</h3>
          <p :if={inspection_list(@inspection, [:actors, :recent]) == []} class="empty">
            No actor contact recorded.
          </p>
          <ol
            :if={inspection_list(@inspection, [:actors, :recent]) != []}
            class="event-list"
          >
            <li :for={actor <- inspection_list(@inspection, [:actors, :recent])} class="event-item">
              <div class="event-title">
                <strong>{actor_name(actor)}</strong>
                <time>{display(map_value(actor, :last_interaction_at))}</time>
              </div>
              <p class="event-data">{actor_detail(actor)}</p>
            </li>
          </ol>
        </article>

        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">Idempotency</p>
              <h2>Effect health</h2>
            </div>
            <span class={"badge #{effect_health_class(@inspection)}"}>
              {effect_health_label(@inspection)}
            </span>
          </div>

          <div class="health-counts" aria-label="Effect counts by state">
            <div :for={state <- effect_states()} class="health-count">
              <strong>{inspection_count(@inspection, [:effects, :counts], state)}</strong>
              <span>{state_label(state)}</span>
            </div>
            <div class="health-count">
              <strong>{inspection_value(@inspection, [:effects, :reconciled], 0)}</strong>
              <span>reconciled</span>
            </div>
          </div>

          <h3 class="subsection-title">Needs attention</h3>
          <p :if={inspection_list(@inspection, [:effects, :attention]) == []} class="empty">
            No reserved, uncertain, or failed effects.
          </p>
          <ol
            :if={inspection_list(@inspection, [:effects, :attention]) != []}
            class="event-list"
          >
            <li
              :for={effect <- inspection_list(@inspection, [:effects, :attention])}
              class="event-item"
            >
              <div class="event-title">
                <strong>{display(map_value(effect, :kind, "effect"))}</strong>
                <span class={"badge #{effect_state_class(effect)}"}>
                  {state_label(map_value(effect, :status, "unknown"))}
                </span>
              </div>
              <p class="event-data">{effect_detail(effect)}</p>
            </li>
          </ol>

          <h3 class="subsection-title">Completed receipts</h3>
          <p
            :if={inspection_list(@inspection, [:effects, :completed_receipts]) == []}
            class="empty"
          >
            No completed receipts recorded.
          </p>
          <ol
            :if={inspection_list(@inspection, [:effects, :completed_receipts]) != []}
            class="event-list"
          >
            <li
              :for={effect <- inspection_list(@inspection, [:effects, :completed_receipts])}
              class="event-item"
            >
              <div class="event-title">
                <strong>{receipt_name(effect)}</strong>
                <time>{display(map_value(effect, :completed_at))}</time>
              </div>
              <p class="event-data">{display(map_value(effect, :operation_key))}</p>
            </li>
          </ol>
        </article>
      </section>

      <section
        :if={@active_tab == "overview"}
        class="health-grid"
        aria-label="SQLite progress and migration status"
      >
        <article class="panel">
          <div class="panel-header">
            <h2>Scan watermarks</h2>
            <span class="count">{length(inspection_list(@inspection, [:scans]))} streams</span>
          </div>
          <p :if={inspection_list(@inspection, [:scans]) == []} class="empty">
            No scan watermarks recorded.
          </p>
          <ol :if={inspection_list(@inspection, [:scans]) != []} class="event-list">
            <li :for={scan <- inspection_list(@inspection, [:scans])} class="event-item">
              <div class="event-title">
                <strong>{display(map_value(scan, :name))}</strong>
                <span class={"badge #{if map_value(scan, :lease_active?, false), do: "active", else: "idle"}"}>
                  {if map_value(scan, :lease_active?, false), do: "Scan active", else: "Idle"}
                </span>
              </div>
              <p class="event-data">
                cursor={display(map_value(scan, :cursor))} · completed={display(
                  map_value(scan, :last_completed_at)
                )}
              </p>
            </li>
          </ol>
        </article>

        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">Durable store</p>
              <h2>SQLite status</h2>
            </div>
            <span class={"badge #{migration_class(@inspection)}"}>
              {state_label(inspection_value(@inspection, [:sqlite, :migrations, :status], "unknown"))}
            </span>
          </div>
          <p class="proposal-copy">{migration_detail(@inspection)}</p>

          <h3 class="subsection-title">Legacy import</h3>
          <p
            :if={inspection_list(@inspection, [:sqlite, :legacy_imports]) == []}
            class="empty"
          >
            No legacy import record. A new installation can use SQLite directly.
          </p>
          <ol
            :if={inspection_list(@inspection, [:sqlite, :legacy_imports]) != []}
            class="event-list"
          >
            <li
              :for={legacy <- inspection_list(@inspection, [:sqlite, :legacy_imports])}
              class="event-item"
            >
              <div class="event-title">
                <strong>{display(map_value(legacy, :name))}</strong>
                <span class="badge healthy">{state_label(map_value(legacy, :status, "unknown"))}</span>
              </div>
              <p class="event-data">{legacy_import_detail(legacy)}</p>
            </li>
          </ol>

          <details :if={@inspection_error} class="technical-details">
            <summary>Inspection error</summary>
            <pre>{@inspection_error}</pre>
          </details>
        </article>
      </section>

      <section :if={@active_tab == "overview"} class="event-grid" aria-label="Recent events">
        <article class="panel">
          <div class="panel-header">
            <h2>Workflow events</h2>
            <span class="count">{length(@workflow_events)} recent</span>
          </div>
          <p :if={@workflow_events == []} class="empty">No workflow events recorded.</p>
          <ol :if={@workflow_events != []} class="event-list">
            <li :for={event <- @workflow_events} class="event-item">
              <div class="event-title">
                <strong>{event_name(event)}</strong>
                <time>{event_time(event)}</time>
              </div>
              <p class="event-data">{event_data(event)}</p>
            </li>
          </ol>
        </article>

        <article class="panel">
          <div class="panel-header">
            <h2>Agent events</h2>
            <span class="count">{length(@agent_events)} recent</span>
          </div>
          <p :if={@agent_events == []} class="empty">No AgentServer events recorded.</p>
          <ol :if={@agent_events != []} class="event-list">
            <li :for={event <- @agent_events} class="event-item">
              <div class="event-title">
                <strong>{event_name(event)}</strong>
                <time>{event_time(event)}</time>
              </div>
              <p class="event-data">{event_data(event)}</p>
            </li>
          </ol>
        </article>
      </section>

      <section
        :if={@active_tab == "overview"}
        class="planned-controls"
        aria-label="Planned controls"
      >
        <div>
          <h2>Planned controls</h2>
          <p>Visible for layout review. No action or approval handlers are installed.</p>
        </div>
        <div class="control-row">
          <button type="button" disabled>Run reactive review</button>
          <button type="button" disabled>Run proactive review</button>
          <button type="button" disabled>Approve human-in-the-loop post</button>
        </div>
      </section>

      <details :if={@active_tab == "overview"} class="about-panel">
        <summary>About this agent</summary>
        <div class="about-content">
          <section>
            <p class="panel-kicker">Character</p>
            <h2>{@character.name}</h2>
            <p>{@character.mission}</p>
            <h3>Traits</h3>
            <div class="tag-list">
              <span :for={trait <- @character.traits} class="tag">{trait}</span>
            </div>
            <h3>Topical scope</h3>
            <ul>
              <li :for={topic <- @character.topical_scope}>{topic}</li>
            </ul>
          </section>
          <section>
            <p class="panel-kicker">Public disclosure</p>
            <h2>Human-agent boundary</h2>
            <p>{display(map_value(@disclosure, :human_review))}</p>
            <p>{display(map_value(@disclosure, :processing))}</p>
            <p>{display(map_value(@disclosure, :local_memory))}</p>
            <p>
              Operator contact:
              <a href={map_value(map_value(@disclosure, :operator, %{}), :contact, "#")}>
                {display(map_value(map_value(@disclosure, :operator, %{}), :contact))}
              </a>
            </p>
          </section>
        </div>
      </details>

      <section
        :if={@active_tab == "simulated-posts"}
        id="simulated-posts-panel"
        class="panel simulated-panel"
        role="tabpanel"
        aria-labelledby="simulated-posts-tab"
      >
        <div class="panel-header">
          <div>
            <p class="panel-kicker">SQLite dry-run history</p>
            <h2>Simulated posts</h2>
          </div>
          <span class="badge safe">
            {if @manual_publish_enabled, do: "Manual publish ready", else: "Local only"}
          </span>
        </div>

        <p class="simulated-intro">
          These drafts were selected by the agent during dry-run cycles. They were stored locally
          and were not sent to DelveTown. A publish button sends only the selected draft. Scheduled
          agent writes stay off. This list refreshes every 3 seconds.
        </p>

        <p
          :if={@publish_notice}
          class={"publish-notice #{map_value(@publish_notice, :kind)}"}
          role="status"
        >
          {map_value(@publish_notice, :text)}
          <a
            :if={post_url(map_value(@publish_notice, :uri), session_actor(@status))}
            href={post_url(map_value(@publish_notice, :uri), session_actor(@status))}
            target="_blank"
            rel="noreferrer"
          >
            View published post ↗
          </a>
        </p>

        <p :if={inspection_list(@inspection, [:simulated_posts]) == []} class="empty">
          No simulated posts yet. A selected reply, welcome, or original post will appear here.
        </p>

        <ol
          :if={inspection_list(@inspection, [:simulated_posts]) != []}
          class="simulated-list"
        >
          <li
            :for={post <- inspection_list(@inspection, [:simulated_posts])}
            class="simulated-card"
          >
            <div class="simulated-card-header">
              <span class="badge idle">{state_label(map_value(post, :action, "post"))}</span>
              <time>{display(map_value(post, :simulated_at))}</time>
            </div>
            <blockquote class="simulated-draft">{simulated_text(post)}</blockquote>
            <div class="simulated-meta">
              <span><strong>Intent:</strong> {display(map_value(post, :intent))}</span>
              <span><strong>Topic:</strong> {display(map_value(post, :topic))}</span>
              <span><strong>Format:</strong> {state_label(map_value(post, :response_format))}</span>
              <span><strong>Reason:</strong> {display(map_value(post, :reason))}</span>
            </div>
            <div class="simulated-actions">
              <a
                :if={post_url(map_value(post, :record_uri))}
                class="source-link"
                href={post_url(map_value(post, :record_uri))}
                target="_blank"
                rel="noreferrer"
              >
                View source context ↗
              </a>
              <a
                :if={published_post_url(post, @status)}
                class="source-link"
                href={published_post_url(post, @status)}
                target="_blank"
                rel="noreferrer"
              >
                View published post ↗
              </a>
              <span :if={published?(post)} class="published-state">Published</span>
              <button
                :if={not published?(post)}
                type="button"
                class="publish-button"
                phx-click="publish_simulated"
                phx-value-event_key={map_value(post, :event_key)}
                phx-disable-with="Publishing…"
                data-confirm="Publish this exact draft to DelveTown?"
                disabled={not @manual_publish_enabled}
              >
                Publish to DelveTown
              </button>
            </div>
          </li>
        </ol>
      </section>

      <p class="footer-note">
        Local dashboard on port {@port}. Scheduled protocol writes remain controlled by the write lock.
      </p>
    </div>
    """
  end

  defp snapshot do
    status_result = safe_read(&JidoDelvetown.status/0)
    status = value_or_empty(status_result)
    events = safe_read(fn -> JidoDelvetown.recent_events(12) end) |> value_or_empty()
    inspection_result = safe_read(fn -> JidoDelvetown.inspect_state(limit: 6) end)
    inspection = value_or_empty(inspection_result)
    character = Personality.character()
    contract = character.extensions.delvetown
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      page_title: "AgentJido / DelveTown",
      status: status,
      status_error: error_text(status_result),
      operational_state: operational_state(status_result, status),
      budget: map_value(status, :budget, %{}),
      decision: map_value(status, :decision, %{}),
      last_cycle: map_value(status, :last_cycle, %{}),
      last_run: map_value(status, :last_run, %{}),
      workflow_events: list_value(events, :workflow),
      agent_events: list_value(events, :agent),
      inspection: inspection,
      inspection_error: error_text(inspection_result),
      character: %{
        name: character.name,
        mission: contract.mission,
        traits: character.personality.traits,
        topical_scope: contract.topical_scope
      },
      disclosure: Personality.disclosure(),
      manual_publish_enabled: JidoDelvetown.Config.manual_publish_enabled?(),
      port: JidoDelvetown.Config.dashboard_port(),
      refreshed_at: DateTime.to_iso8601(now),
      refreshed_label: Calendar.strftime(now, "%H:%M:%S UTC")
    }
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  defp active_tab(%{"tab" => "simulated-posts"}), do: "simulated-posts"
  defp active_tab(_params), do: "overview"

  defp safe_read(fun) do
    case fun.() do
      {:error, reason} -> {:error, reason}
      value -> {:ok, value}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp value_or_empty({:ok, value}) when is_map(value), do: value
  defp value_or_empty(_result), do: %{}

  defp error_text({:error, reason}), do: inspect(reason, pretty: true, limit: 20)
  defp error_text(_result), do: nil

  defp operational_state({:error, _reason}, _status) do
    %{
      key: "attention",
      label: "Needs attention",
      effect: "The Agent runtime is unavailable. Scheduled work cannot run.",
      next: "Start the local runtime and wait for the next refresh."
    }
  end

  defp operational_state(_result, status) do
    cond do
      map_value(status, :writes_enabled?, false) ->
        %{
          key: "active",
          label: "Writes enabled",
          effect: "Scheduled Agent work can create public protocol effects.",
          next: "Use the review path before any future one-click action."
        }

      map_value(status, :dry_run_mark_actioned?, false) ->
        %{
          key: "safe",
          label: "Dry run: actions simulated",
          effect: "Protocol effects are blocked. Selected actions advance local dry-run memory.",
          next: "A simulated action is not published and will not run again."
        }

      true ->
        %{
          key: "safe",
          label: "Safe: writes off",
          effect: "Protocol effects are blocked. Review cycles can inspect and propose.",
          next: nil
        }
    end
  end

  defp list_value(map, key) do
    case map_value(map, key, []) do
      value when is_list(value) -> value
      _value -> []
    end
  end

  defp inspection_value(inspection, path, default \\ nil)

  defp inspection_value(value, [], _default), do: value

  defp inspection_value(map, [key | rest], default) when is_map(map) do
    case map_value(map, key, :missing) do
      :missing -> default
      value -> inspection_value(value, rest, default)
    end
  end

  defp inspection_value(_value, _path, default), do: default

  defp inspection_list(inspection, path) do
    case inspection_value(inspection, path, []) do
      value when is_list(value) -> value
      _value -> []
    end
  end

  defp inspection_count(inspection, path, state) do
    inspection
    |> inspection_value(path, %{})
    |> map_value(state, 0)
  end

  defp event_states, do: ~w(pending claimed completed ignored failed)
  defp effect_states, do: ~w(reserved uncertain completed permanent_failure)

  defp tab_class(active_tab, tab) when active_tab == tab, do: "active"
  defp tab_class(_active_tab, _tab), do: ""

  defp simulated_text(post) do
    case map_value(post, :text) do
      text when is_binary(text) and text != "" -> text
      _text -> "Draft text was not stored for this older simulated action."
    end
  end

  defp published?(post), do: map_value(post, :published_status) == "completed"

  defp published_post_url(post, status) do
    post_url(map_value(post, :published_uri), session_actor(status))
  end

  defp publish_error(:manual_publish_disabled),
    do: "Manual publishing is off. Set DELVETOWN_MANUAL_PUBLISH_ENABLED=true and restart."

  defp publish_error(:not_found), do: "The saved simulated draft was not found."
  defp publish_error(:not_simulated), do: "This item is not a simulated draft."
  defp publish_error(:invalid_draft_text), do: "The saved draft text is not valid."
  defp publish_error(:missing_reply_target), do: "The reply target could not be loaded."
  defp publish_error(_reason), do: "DelveTown did not accept the draft. Check the local logs."

  defp publisher,
    do: Application.get_env(:jido_delvetown, :manual_publisher, ManualPublisher)

  defp state_label(value) do
    value
    |> display()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp actor_name(actor) do
    map_value(actor, :handle) || map_value(actor, :display_name) ||
      display(map_value(actor, :did))
  end

  defp actor_detail(actor) do
    contacts = map_value(actor, :contact_count, 0)
    welcome = display(map_value(actor, :welcome_status, "not sent"))
    opt_out = if map_value(actor, :opted_out?, false), do: " · opted out", else: ""
    "#{contacts} contacts · welcome #{welcome}#{opt_out}"
  end

  defp effect_detail(effect) do
    attempts = map_value(effect, :attempt_count, 0)
    key = display(map_value(effect, :operation_key))
    "#{key} · #{attempts} attempts"
  end

  defp receipt_name(effect) do
    effect
    |> map_value(:receipt, %{})
    |> map_value(:uri, map_value(effect, :rkey, "completed effect"))
    |> display()
  end

  defp effect_state_class(effect) do
    case map_value(effect, :status) do
      "permanent_failure" -> "attention"
      "uncertain" -> "attention"
      "reserved" -> "active"
      _status -> "idle"
    end
  end

  defp effect_health_label(inspection) do
    if inspection_list(inspection, [:effects, :attention]) == [], do: "Healthy", else: "Review"
  end

  defp effect_health_class(inspection) do
    if inspection_list(inspection, [:effects, :attention]) == [],
      do: "healthy",
      else: "attention"
  end

  defp migration_class(inspection) do
    if inspection_value(inspection, [:sqlite, :migrations, :status]) == "current",
      do: "healthy",
      else: "attention"
  end

  defp migration_detail(inspection) do
    applied = inspection_list(inspection, [:sqlite, :migrations, :applied]) |> length()
    pending = inspection_list(inspection, [:sqlite, :migrations, :pending]) |> length()
    "#{applied} migrations applied · #{pending} pending"
  end

  defp legacy_import_detail(legacy) do
    counts = map_value(legacy, :counts, %{})
    effects = map_value(counts, "effects", 0)
    events = map_value(counts, "events", 0)
    checkpoints = map_value(counts, "checkpoints", 0)
    "#{effects} effects · #{events} events · #{checkpoints} checkpoints"
  end

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp display(nil), do: "—"
  defp display(""), do: "—"
  defp display(value) when is_binary(value), do: value
  defp display(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp display(value), do: inspect(value, pretty: true, limit: 12)

  defp write_switch_class(status) do
    if map_value(status, :writes_enabled?, false), do: "on", else: "off"
  end

  defp write_switch_label(status) do
    if map_value(status, :writes_enabled?, false) do
      "Protocol writes are enabled. This control only reports status."
    else
      "Protocol writes are disabled. This control only reports status."
    end
  end

  defp runtime_label(nil), do: "Healthy"
  defp runtime_label(_error), do: "Needs attention"
  defp runtime_class(nil), do: "healthy"
  defp runtime_class(_error), do: "attention"
  defp runtime_detail(nil), do: "Agent process is available"
  defp runtime_detail(_error), do: "Agent state is not available"

  defp session_name(status) do
    session = map_value(status, :session, %{})

    if map_value(session, :connected?, false), do: "Healthy", else: "Idle"
  end

  defp session_detail(status) do
    session = map_value(status, :session, %{})

    cond do
      map_value(session, :connected?, false) -> display(map_value(session, :handle, "Connected"))
      map_value(status, :credentials_configured?, false) -> "Credentials ready"
      true -> "Not connected"
    end
  end

  defp session_class(status) do
    session = map_value(status, :session, %{})
    if map_value(session, :connected?, false), do: "healthy", else: "idle"
  end

  defp schedule_label(status) do
    if map_value(status, :schedule_enabled?, false), do: "Healthy", else: "Needs attention"
  end

  defp schedule_class(status) do
    if map_value(status, :schedule_enabled?, false), do: "healthy", else: "attention"
  end

  defp schedule_detail(status) do
    if map_value(status, :schedule_enabled?, false) do
      "Cron #{display(map_value(status, :cron))}"
    else
      "No reactive schedule loaded"
    end
  end

  defp profile_url(status) do
    case session_actor(status) do
      actor when is_binary(actor) and actor != "" ->
        "https://delve.town/profile/#{URI.encode_www_form(actor)}"

      _actor ->
        nil
    end
  end

  defp session_actor(status) do
    session = map_value(status, :session, %{})
    map_value(session, :handle) || map_value(session, :did)
  end

  defp post_url(uri, actor \\ nil)

  defp post_url(uri, actor) when is_binary(uri) do
    case Regex.run(
           ~r{\Aat://([^/]+)/town\.delve\.feed\.post/([^/]+)\z},
           uri,
           capture: :all_but_first
         ) do
      [repo, rkey] ->
        actor = if is_binary(actor) and actor != "", do: actor, else: repo

        "https://delve.town/profile/#{URI.encode_www_form(actor)}/post/#{URI.encode_www_form(rkey)}"

      _invalid ->
        nil
    end
  end

  defp post_url(_uri, _actor), do: nil

  defp published_uri(last_run, events) do
    map_value(last_run, :record_uri) ||
      Enum.find_value(events, fn event ->
        event
        |> map_value(:data, %{})
        |> map_value(:record_uri)
      end)
  end

  defp event_name(event) do
    event
    |> map_value(:type, map_value(event, :name, "event"))
    |> display()
  end

  defp event_time(event) do
    event
    |> map_value(:at, map_value(event, :timestamp, ""))
    |> display()
  end

  defp event_data(event) do
    event
    |> map_value(:data, map_value(event, :payload, %{}))
    |> display()
  end
end
