defmodule JidoDelvetownWeb.DashboardComponents do
  @moduledoc false

  use Phoenix.Component

  @spec styles(map()) :: Phoenix.LiveView.Rendered.t()
  def styles(assigns), do: content(assign(assigns, :dashboard_section, :styles))

  @spec sidebar_navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def sidebar_navigation(assigns),
    do: content(assign(assigns, :dashboard_section, :sidebar_navigation))

  @spec mobile_navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def mobile_navigation(assigns),
    do: content(assign(assigns, :dashboard_section, :mobile_navigation))

  @spec first_run_setup(map()) :: Phoenix.LiveView.Rendered.t()
  def first_run_setup(assigns),
    do: content(assign(assigns, :dashboard_section, :first_run_setup))

  @spec operational_state(map()) :: Phoenix.LiveView.Rendered.t()
  def operational_state(assigns),
    do: content(assign(assigns, :dashboard_section, :operational_state))

  @spec overview(map()) :: Phoenix.LiveView.Rendered.t()
  def overview(assigns), do: content(assign(assigns, :dashboard_section, :overview))

  @spec inbox(map()) :: Phoenix.LiveView.Rendered.t()
  def inbox(assigns), do: content(assign(assigns, :dashboard_section, :inbox))

  @spec runtime_health(map()) :: Phoenix.LiveView.Rendered.t()
  def runtime_health(assigns), do: content(assign(assigns, :dashboard_section, :runtime_health))

  @spec memory_and_effects(map()) :: Phoenix.LiveView.Rendered.t()
  def memory_and_effects(assigns),
    do: content(assign(assigns, :dashboard_section, :memory_and_effects))

  @spec scan_and_database_status(map()) :: Phoenix.LiveView.Rendered.t()
  def scan_and_database_status(assigns),
    do: content(assign(assigns, :dashboard_section, :scan_and_database_status))

  @spec recent_events(map()) :: Phoenix.LiveView.Rendered.t()
  def recent_events(assigns), do: content(assign(assigns, :dashboard_section, :recent_events))

  @spec planned_controls(map()) :: Phoenix.LiveView.Rendered.t()
  def planned_controls(assigns),
    do: content(assign(assigns, :dashboard_section, :planned_controls))

  @spec agent_information(map()) :: Phoenix.LiveView.Rendered.t()
  def agent_information(assigns),
    do: content(assign(assigns, :dashboard_section, :agent_information))

  @spec drafts(map()) :: Phoenix.LiveView.Rendered.t()
  def drafts(assigns), do: content(assign(assigns, :dashboard_section, :drafts))

  @spec settings(map()) :: Phoenix.LiveView.Rendered.t()
  def settings(assigns), do: content(assign(assigns, :dashboard_section, :settings))

  @spec footer(map()) :: Phoenix.LiveView.Rendered.t()
  def footer(assigns), do: content(assign(assigns, :dashboard_section, :footer))

  defp content(assigns) do
    ~H"""
    <style :if={@dashboard_section == :styles}>
      :root {
        --font-sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        --font-mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        --space-1: 4px;
        --space-2: 8px;
        --space-3: 12px;
        --space-4: 16px;
        --space-5: 20px;
        --space-6: 24px;
        --radius-sm: 9px;
        --radius: 14px;
        --radius-lg: 18px;
        --motion-fast: 160ms ease;
      }

      :root,
      .console-root[data-theme="light"] {
        color-scheme: light;
        --canvas: #f7f7f5;
        --surface: #ffffff;
        --surface-raised: #f0f1ef;
        --line: #e0e2de;
        --line-strong: #c5c8c2;
        --text: #191a18;
        --muted: #5f645d;
        --quiet: #7a7f77;
        --green: #18733f;
        --green-deep: #e4f3e9;
        --cyan: #315ea8;
        --cyan-deep: #e7edf8;
        --amber: #8a5a0a;
        --amber-deep: #f8ebca;
        --red: #aa3939;
        --red-deep: #f8e0df;
        --preview-bg: #eceeeb;
        --control-disabled: #eceeeb;
        --control-disabled-text: #6d716b;
        --sidebar: #f1f2ef;
        --sidebar-raised: #ffffff;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          color-scheme: dark;
          --canvas: #0b0c0c;
          --surface: #121313;
          --surface-raised: #1a1c1b;
          --line: #2a2d2b;
          --line-strong: #414541;
          --text: #f0f1ee;
          --muted: #aaaea7;
          --quiet: #81867f;
          --green: #70d99b;
          --green-deep: #153524;
          --cyan: #8aa8e8;
          --cyan-deep: #1d2a45;
          --amber: #ffcb6b;
          --amber-deep: #44331a;
          --red: #ff948f;
          --red-deep: #451f20;
          --preview-bg: #080909;
          --control-disabled: #1b1d1c;
          --control-disabled-text: #939891;
          --sidebar: #0f1010;
          --sidebar-raised: #171918;
        }
      }

      .console-root[data-theme="dark"] {
        color-scheme: dark;
        --canvas: #0b0c0c;
        --surface: #121313;
        --surface-raised: #1a1c1b;
        --line: #2a2d2b;
        --line-strong: #414541;
        --text: #f0f1ee;
        --muted: #aaaea7;
        --quiet: #81867f;
        --green: #70d99b;
        --green-deep: #153524;
        --cyan: #8aa8e8;
        --cyan-deep: #1d2a45;
        --amber: #ffcb6b;
        --amber-deep: #44331a;
        --red: #ff948f;
        --red-deep: #451f20;
        --preview-bg: #080909;
        --control-disabled: #1b1d1c;
        --control-disabled-text: #939891;
        --sidebar: #0f1010;
        --sidebar-raised: #171918;
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        background: var(--canvas);
        color: var(--text);
        font-family: var(--font-sans);
        font-size: 15px;
        line-height: 1.5;
      }

      .console-root {
        min-height: 100vh;
        background: var(--canvas);
        color: var(--text);
      }

      button, summary, a { font: inherit; }

      a { color: var(--cyan); }

      :focus-visible {
        outline: 3px solid var(--cyan);
        outline-offset: 3px;
      }

      .operator-layout {
        display: grid;
        grid-template-columns: 248px minmax(0, 1fr);
        width: min(1480px, 100%);
        min-height: 100vh;
        margin: 0 auto;
      }

      .operator-workspace { min-width: 0; }

      .operator-sidebar {
        position: sticky;
        top: 0;
        display: flex;
        height: 100vh;
        flex-direction: column;
        gap: var(--space-6);
        overflow-y: auto;
        padding: 24px 18px;
        border-right: 1px solid var(--line);
        background: var(--sidebar);
      }

      .operator-brand {
        display: flex;
        align-items: center;
        gap: 11px;
        color: var(--text);
        text-decoration: none;
      }

      .operator-mark {
        display: grid;
        width: 36px;
        height: 36px;
        flex: 0 0 36px;
        place-items: center;
        border: 1px solid var(--line-strong);
        border-radius: 9px;
        background: var(--text);
        color: var(--canvas);
        font-family: var(--font-mono);
        font-size: 14px;
        font-weight: 800;
      }

      .operator-brand-copy { display: grid; gap: 1px; }
      .operator-brand-copy strong { font-size: 14px; letter-spacing: -0.01em; }
      .operator-brand-copy span { color: var(--muted); font-size: 11px; }

      .operator-nav { display: grid; gap: 5px; }

      .operator-nav-label {
        margin: 0 9px 4px;
        color: var(--quiet);
        font-size: 10px;
        font-weight: 760;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .operator-nav-link {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        min-height: 40px;
        padding: 8px 10px;
        border: 1px solid transparent;
        border-radius: var(--radius-sm);
        color: var(--muted);
        font-size: 13px;
        font-weight: 680;
        text-decoration: none;
        transition: background var(--motion-fast), border-color var(--motion-fast), color var(--motion-fast);
      }

      .operator-nav-link:hover {
        border-color: var(--line);
        background: var(--sidebar-raised);
        color: var(--text);
      }

      .operator-nav-link.active {
        border-color: color-mix(in srgb, var(--cyan) 32%, var(--line));
        background: var(--cyan-deep);
        color: var(--cyan);
      }

      .operator-nav-link[aria-disabled="true"] {
        color: var(--quiet);
        cursor: default;
        opacity: 0.58;
      }

      .operator-nav-link[aria-disabled="true"]:hover {
        border-color: transparent;
        background: transparent;
      }

      .nav-count {
        min-width: 22px;
        padding: 1px 6px;
        border: 1px solid color-mix(in srgb, currentColor 20%, transparent);
        border-radius: 99px;
        font-size: 10px;
        text-align: center;
      }

      .nav-soon {
        color: var(--quiet);
        font-size: 9px;
        font-weight: 720;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      .global-agent-state {
        display: grid;
        gap: 12px;
        margin-top: auto;
        padding: 14px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--sidebar-raised);
      }

      .global-state-heading {
        display: flex;
        align-items: start;
        gap: 10px;
      }

      .global-state-heading .state-dot { margin-top: 5px; }
      .global-state-copy { display: grid; min-width: 0; gap: 1px; }
      .global-state-copy span { color: var(--quiet); font-size: 10px; text-transform: uppercase; }
      .global-state-copy strong { font-size: 13px; line-height: 1.3; }

      .global-state-effect {
        margin: 0;
        color: var(--muted);
        font-size: 11px;
        line-height: 1.45;
      }

      .global-agent-state .technical-details {
        margin: 0;
        font-size: 11px;
      }

      .global-write-state {
        display: flex;
        align-items: center;
        justify-content: space-between;
        width: 100%;
        padding: 8px 9px;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--surface-raised);
        color: var(--muted);
        font-size: 10px;
        font-weight: 760;
        letter-spacing: 0.06em;
        text-transform: uppercase;
      }

      .global-write-state strong { color: var(--text); font-size: 11px; }
      .global-write-state.on strong { color: var(--amber); }

      .sidebar-meta {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        color: var(--quiet);
        font-size: 10px;
      }

      .sidebar-meta a { color: var(--muted); text-decoration: none; }
      .sidebar-meta a:hover { color: var(--text); }

      .mobile-console-header { display: none; }

      .dashboard-shell {
        width: min(1180px, calc(100% - 48px));
        margin: 0 auto;
        padding: 30px 0 44px;
      }

      .setup-page {
        width: min(100%, 860px);
        margin: 0 auto;
      }

      .setup-header {
        margin-bottom: 24px;
      }

      .setup-header h1 {
        margin: 4px 0 10px;
        font-size: clamp(28px, 4vw, 40px);
      }

      .setup-lede {
        max-width: 66ch;
        margin: 0;
        color: var(--muted);
        font-size: 15px;
      }

      .setup-steps {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
        margin: 20px 0 0;
        padding: 0;
        list-style: none;
      }

      .setup-steps li {
        display: flex;
        align-items: center;
        gap: 8px;
        color: var(--muted);
        font-size: 12px;
        font-weight: 680;
      }

      .setup-steps span {
        display: grid;
        width: 24px;
        height: 24px;
        flex: 0 0 24px;
        place-items: center;
        border: 1px solid var(--line-strong);
        border-radius: 50%;
        background: var(--surface);
        color: var(--cyan);
        font-family: var(--font-mono);
        font-size: 10px;
      }

      .setup-notice {
        display: grid;
        gap: 4px;
        margin-bottom: 16px;
        padding: 14px 16px;
        border: 1px solid color-mix(in srgb, var(--green) 45%, var(--line));
        border-radius: var(--radius);
        background: color-mix(in srgb, var(--green-deep) 60%, var(--surface));
      }

      .setup-notice.attention {
        border-color: color-mix(in srgb, var(--red) 45%, var(--line));
        background: color-mix(in srgb, var(--red-deep) 55%, var(--surface));
      }

      .setup-notice strong { font-size: 14px; }
      .setup-notice p { margin: 0; color: var(--muted); font-size: 13px; }

      .setup-notice-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-top: 8px;
      }

      .setup-form { display: grid; gap: 14px; }

      .setup-card {
        display: grid;
        grid-template-columns: minmax(160px, 0.42fr) minmax(0, 1fr);
        gap: 28px;
        padding: 22px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface);
      }

      .setup-card-copy h2 { margin: 3px 0 6px; }
      .setup-card-copy p:last-child { margin: 0; color: var(--muted); font-size: 12px; }
      .setup-card-fields { display: grid; gap: 14px; }

      .setup-field { display: grid; gap: 5px; }

      .setup-field label,
      .setup-field legend {
        color: var(--text);
        font-size: 12px;
        font-weight: 720;
      }

      .setup-field input,
      .setup-field select {
        width: 100%;
        min-height: 42px;
        padding: 9px 11px;
        border: 1px solid var(--line-strong);
        border-radius: var(--radius-sm);
        background: var(--canvas);
        color: var(--text);
        font: inherit;
      }

      .setup-field input::placeholder { color: var(--quiet); }

      .setup-help {
        margin: 0;
        color: var(--quiet);
        font-size: 11px;
      }

      .setup-key-status {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 11px 12px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        background: var(--surface-raised);
      }

      .setup-key-status div { min-width: 0; }
      .setup-key-status p { margin: 0; color: var(--muted); font-size: 11px; }
      .setup-key-status code { color: var(--text); font-family: var(--font-mono); font-size: 12px; }

      .setup-autonomy {
        display: grid;
        gap: 8px;
        margin: 0;
        padding: 0;
        border: 0;
      }

      .setup-autonomy legend { margin-bottom: 2px; }

      .setup-choice {
        display: grid;
        grid-template-columns: 18px minmax(0, 1fr);
        gap: 2px 9px;
        padding: 11px 12px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        background: var(--canvas);
        cursor: pointer;
      }

      .setup-choice:has(input:checked) {
        border-color: color-mix(in srgb, var(--cyan) 55%, var(--line));
        background: var(--cyan-deep);
      }

      .setup-choice input { width: 16px; min-height: 16px; margin: 2px 0 0; }
      .setup-choice strong { font-size: 13px; }
      .setup-choice span { grid-column: 2; color: var(--muted); font-size: 11px; }

      .setup-actions {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding: 4px 2px 0;
      }

      .setup-actions p { max-width: 52ch; margin: 0; color: var(--muted); font-size: 11px; }

      .setup-primary,
      .setup-secondary {
        min-height: 40px;
        padding: 8px 14px;
        border: 1px solid var(--line-strong);
        border-radius: var(--radius-sm);
        font: inherit;
        font-size: 13px;
        font-weight: 720;
        cursor: pointer;
      }

      .setup-primary {
        border-color: color-mix(in srgb, var(--cyan) 62%, var(--line));
        background: var(--cyan-deep);
        color: var(--text);
      }

      .setup-primary:hover { border-color: var(--cyan); }

      .setup-secondary {
        background: var(--surface);
        color: var(--muted);
      }

      .setup-secondary:hover { color: var(--text); }

      .page-header {
        display: flex;
        align-items: end;
        justify-content: space-between;
        gap: 24px;
        margin-bottom: 18px;
      }

      .header-meta {
        display: flex;
        align-items: end;
        gap: var(--space-4);
      }

      .theme-control {
        display: grid;
        gap: var(--space-1);
      }

      .theme-control label {
        color: var(--muted);
        font-size: 11px;
        font-weight: 720;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      .theme-control select {
        min-height: 36px;
        padding: 6px 28px 6px 10px;
        border: 1px solid var(--line-strong);
        border-radius: var(--radius-sm);
        background: var(--surface);
        color: var(--text);
        cursor: pointer;
      }

      .eyebrow,
      .panel-kicker,
      .metric-label {
        margin: 0;
        color: var(--cyan);
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

      .state-dot {
        width: 11px;
        height: 11px;
        flex: 0 0 auto;
        border-radius: 50%;
        background: var(--green);
        box-shadow: 0 0 0 5px color-mix(in srgb, var(--green) 12%, transparent);
      }

      .state-attention .state-dot {
        background: var(--red);
        box-shadow: 0 0 0 5px color-mix(in srgb, var(--red) 12%, transparent);
      }

      .state-active .state-dot {
        background: var(--amber);
        box-shadow: 0 0 0 5px color-mix(in srgb, var(--amber) 12%, transparent);
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
        background: color-mix(in srgb, var(--surface) 72%, transparent);
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
        background: color-mix(in srgb, var(--surface) 90%, transparent);
      }

      .overview-stack {
        display: grid;
        gap: 16px;
        margin-bottom: 16px;
      }

      .overview-summary-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 12px;
      }

      .overview-summary-card {
        display: grid;
        align-content: start;
        min-height: 174px;
      }

      .overview-summary-card .panel-header { margin-bottom: 18px; }

      .overview-value {
        margin: 0 0 8px;
        color: var(--text);
        font-size: 25px;
        font-weight: 760;
        letter-spacing: -0.025em;
      }

      .overview-detail {
        margin: 0;
        color: var(--muted);
        font-size: 13px;
        line-height: 1.5;
      }

      .overview-schedule-list {
        display: grid;
        gap: 7px;
        margin: 2px 0 0;
        padding: 0;
        list-style: none;
      }

      .overview-schedule-list li {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
        color: var(--muted);
        font-size: 12px;
      }

      .overview-schedule-list strong { color: var(--text); font-weight: 680; }
      .overview-schedule-list time { color: var(--cyan); white-space: nowrap; }

      .overview-detail-grid {
        display: grid;
        grid-template-columns: minmax(0, 0.82fr) minmax(0, 1.18fr);
        gap: 16px;
      }

      .overview-attention-list {
        display: grid;
        gap: 8px;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      .overview-attention-item {
        padding: 11px 12px;
        border: 1px solid var(--line);
        border-left: 3px solid var(--red);
        border-radius: var(--radius-sm);
        background: var(--surface-raised);
      }

      .overview-attention-item.idle { border-left-color: var(--cyan); }
      .overview-attention-item strong { display: block; margin-bottom: 3px; font-size: 13px; }
      .overview-attention-item p { margin: 0; color: var(--muted); font-size: 12px; }

      .overview-budget-list {
        display: grid;
        gap: 13px;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      .overview-budget-heading {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 5px;
        font-size: 12px;
      }

      .overview-budget-heading strong { color: var(--text); }
      .overview-budget-heading span { color: var(--muted); }

      .overview-budget-track {
        height: 7px;
        overflow: hidden;
        border-radius: 99px;
        background: var(--surface-raised);
      }

      .overview-budget-track span {
        display: block;
        width: var(--budget-use);
        height: 100%;
        border-radius: inherit;
        background: var(--cyan);
      }

      .overview-actions .event-data { font-family: var(--font-sans); }

      .overview-actions .event-item > time {
        display: block;
        margin-top: 6px;
        color: var(--quiet);
        font-size: 11px;
      }

      .inbox-shell {
        display: grid;
        gap: 16px;
        margin-bottom: 16px;
      }

      .inbox-command-bar {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(280px, 0.72fr);
        gap: 20px;
        align-items: start;
      }

      .inbox-command-copy h2 { margin: 4px 0 8px; }
      .inbox-command-copy > p:last-child { margin: 0; color: var(--muted); }

      .inbox-scan-control {
        display: grid;
        gap: 10px;
        padding: 14px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        background: var(--surface-raised);
      }

      .inbox-scan-control .run-review-button { width: 100%; }

      .inbox-scan-meta {
        margin: 0;
        color: var(--quiet);
        font-size: 11px;
      }

      .inbox-category-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 8px;
        margin-top: 18px;
      }

      .inbox-category {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 8px;
        padding: 10px 12px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        color: var(--muted);
        font-size: 12px;
      }

      .inbox-category strong { color: var(--text); font-size: 17px; }

      .inbox-event-list {
        display: grid;
        gap: 10px;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      .inbox-event-card {
        display: grid;
        grid-template-columns: minmax(150px, 0.34fr) minmax(0, 1fr);
        gap: 16px;
        padding: 15px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        background: var(--surface-raised);
      }

      .inbox-event-identity,
      .inbox-event-body { min-width: 0; }

      .inbox-event-kind {
        display: flex;
        align-items: center;
        gap: 7px;
        margin-bottom: 8px;
      }

      .inbox-event-identity strong { display: block; overflow-wrap: anywhere; }
      .inbox-event-identity time { color: var(--quiet); font-size: 11px; }

      .inbox-event-body > p {
        margin: 0;
        color: var(--muted);
        font-size: 12px;
        line-height: 1.5;
      }

      .inbox-proposal {
        display: grid;
        gap: 7px;
        padding: 11px 12px;
        border-left: 3px solid var(--cyan);
        border-radius: var(--radius-sm);
        background: var(--surface);
      }

      .inbox-proposal-heading {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        font-size: 12px;
      }

      .inbox-proposal blockquote { margin: 0; color: var(--text); font-size: 13px; }
      .inbox-proposal p { margin: 0; color: var(--muted); font-size: 12px; }

      .inbox-source-link {
        display: inline-block;
        margin-top: 9px;
        color: var(--cyan);
        font-size: 12px;
        font-weight: 650;
        text-decoration: none;
      }

      .inbox-panel-meta {
        display: flex;
        align-items: center;
        gap: 9px;
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
        color: var(--cyan);
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
        border-left: 3px solid var(--cyan);
        border-radius: 0 8px 8px 0;
        background: color-mix(in srgb, var(--cyan) 6%, var(--surface));
        color: var(--text);
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
        background: color-mix(in srgb, var(--surface-raised) 72%, transparent);
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
        font-family: var(--font-mono);
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

      .drafts-shell {
        display: grid;
        gap: 16px;
        margin-bottom: 18px;
      }

      .drafts-summary { display: grid; gap: 2px; }

      .draft-state-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 8px;
      }

      .draft-state-grid > div {
        display: grid;
        gap: 1px;
        padding: 11px 12px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        background: var(--surface-raised);
      }

      .draft-state-grid strong { color: var(--text); font-size: 19px; }
      .draft-state-grid span { color: var(--muted); font-size: 11px; }

      .draft-section { display: grid; gap: 12px; }
      .draft-section .panel-header { margin-bottom: 0; }

      .draft-card {
        box-shadow: 0 1px 0 color-mix(in srgb, var(--line) 45%, transparent);
      }

      .social-preview-author {
        display: flex;
        align-items: center;
        gap: 9px;
        margin-bottom: 11px;
      }

      .social-preview-author > span:last-child { display: grid; min-width: 0; }
      .social-preview-author strong { color: var(--text); font-size: 13px; }
      .social-preview-author small { color: var(--quiet); font-size: 11px; }

      .social-avatar {
        display: grid;
        width: 32px;
        height: 32px;
        flex: 0 0 32px;
        place-items: center;
        border-radius: 50%;
        background: var(--text);
        color: var(--canvas);
        font-family: var(--font-mono);
        font-size: 11px;
        font-weight: 800;
      }

      .social-avatar.muted {
        border: 1px solid var(--line-strong);
        background: var(--surface);
        color: var(--muted);
      }

      .simulated-intro {
        max-width: 72ch;
        margin-bottom: 18px;
        color: var(--muted);
      }

      .like-proposal-section {
        display: grid;
        gap: 12px;
        margin-bottom: 20px;
        padding-bottom: 20px;
        border-bottom: 1px solid var(--line);
      }

      .like-proposal-section .panel-header,
      .like-proposal-section h3,
      .like-target-author { margin-bottom: 0; }

      .like-target-author { color: var(--cyan); }

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
        background: color-mix(in srgb, var(--cyan) 6%, var(--surface));
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
        border: 1px solid color-mix(in srgb, var(--green) 48%, transparent);
        border-radius: 9px;
        background: color-mix(in srgb, var(--green-deep) 50%, var(--surface));
        color: var(--text);
      }

      .publish-notice.attention {
        border-color: color-mix(in srgb, var(--red) 55%, transparent);
        background: color-mix(in srgb, var(--red-deep) 48%, var(--surface));
      }

      .simulated-actions {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 9px 14px;
      }

      .draft-review-actions {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 8px;
        margin-left: auto;
      }

      .review-button {
        min-height: 38px;
        padding: 8px 13px;
        border: 1px solid var(--line-strong);
        border-radius: 9px;
        background: var(--surface);
        color: var(--text);
        cursor: pointer;
        font-size: 13px;
        font-weight: 720;
      }

      .review-button.approve {
        border-color: color-mix(in srgb, var(--green) 52%, var(--line));
        color: var(--green);
      }

      .review-button.reject { color: var(--red); }
      .review-button:hover { border-color: currentColor; }
      .draft-review-actions .publish-button { margin-left: 0; }

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
        border: 1px solid color-mix(in srgb, var(--cyan) 65%, transparent);
        border-radius: 9px;
        background: var(--cyan-deep);
        color: var(--text);
        cursor: pointer;
        font-size: 13px;
        font-weight: 720;
      }

      .publish-button:hover { border-color: var(--cyan); }

      .publish-button:disabled {
        border-color: var(--line);
        background: var(--control-disabled);
        color: var(--quiet);
        cursor: not-allowed;
      }

      .published-state {
        margin-left: auto;
        color: var(--green);
        font-size: 12px;
        font-weight: 680;
      }

      .image-draft-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 14px;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      .image-draft-card {
        display: grid;
        grid-template-rows: auto 1fr;
        overflow: hidden;
        border: 1px solid var(--line);
        border-radius: 11px;
        background: var(--surface-raised);
      }

      .image-preview {
        display: block;
        width: 100%;
        height: 260px;
        object-fit: contain;
        background: var(--preview-bg);
        border-bottom: 1px solid var(--line);
      }

      .image-draft-body {
        display: flex;
        flex-direction: column;
        gap: 12px;
        padding: 16px;
      }

      .image-draft-body h3 { margin-bottom: 0; overflow-wrap: anywhere; }
      .image-caption { margin-bottom: 0; white-space: pre-wrap; }

      .image-alt {
        margin-bottom: 0;
        color: var(--muted);
        font-size: 13px;
      }

      .image-state-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 7px;
      }

      .image-state {
        min-width: 0;
        padding: 8px;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: color-mix(in srgb, var(--canvas) 45%, transparent);
      }

      .image-state span {
        display: block;
        color: var(--quiet);
        font-size: 10px;
        font-weight: 720;
        letter-spacing: 0.05em;
        text-transform: uppercase;
      }

      .image-state strong {
        display: block;
        overflow: hidden;
        margin-top: 2px;
        color: var(--text);
        font-size: 12px;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .image-file-meta {
        margin-bottom: 0;
        color: var(--quiet);
        font-family: var(--font-mono);
        font-size: 11px;
        overflow-wrap: anywhere;
      }

      .settings-shell {
        display: grid;
        gap: 16px;
        margin-bottom: 18px;
      }

      .settings-intro {
        display: flex;
        align-items: start;
        justify-content: space-between;
        gap: 18px;
      }

      .settings-version {
        flex: 0 0 auto;
        padding: 5px 9px;
        border: 1px solid var(--line);
        border-radius: 99px;
        color: var(--muted);
        font-family: var(--font-mono);
        font-size: 11px;
      }

      .settings-form { display: grid; gap: 14px; }

      .settings-section {
        padding: 18px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface);
      }

      .settings-section-heading { margin-bottom: 16px; }
      .settings-section-heading h2 { margin-bottom: 3px; font-size: 18px; }
      .settings-section-heading p { margin: 0; color: var(--muted); font-size: 13px; }

      .settings-field-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 15px;
      }

      .settings-field {
        display: grid;
        align-content: start;
        gap: 6px;
        min-width: 0;
      }

      .settings-field.full { grid-column: 1 / -1; }

      .settings-label-row {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
      }

      .settings-label-row label,
      .settings-legend {
        color: var(--text);
        font-size: 13px;
        font-weight: 700;
      }

      .activation-chip {
        flex: 0 0 auto;
        color: var(--cyan);
        font-size: 10px;
        font-weight: 720;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }

      .settings-field input[type="text"],
      .settings-field input[type="password"],
      .settings-field input[type="number"],
      .settings-field select {
        width: 100%;
        min-height: 42px;
        padding: 8px 10px;
        border: 1px solid var(--line-strong);
        border-radius: 9px;
        background: var(--surface-raised);
        color: var(--text);
        font: inherit;
      }

      .settings-field input[type="text"]:focus,
      .settings-field input[type="password"]:focus,
      .settings-field input[type="number"]:focus,
      .settings-field select:focus { border-color: var(--cyan); }

      .settings-help {
        margin: 0;
        color: var(--quiet);
        font-size: 11px;
        line-height: 1.45;
      }

      .settings-check,
      .settings-option {
        display: flex;
        align-items: start;
        gap: 9px;
        color: var(--muted);
        font-size: 13px;
      }

      .settings-check input,
      .settings-option input { margin-top: 3px; accent-color: var(--cyan); }

      .settings-options {
        display: flex;
        flex-wrap: wrap;
        gap: 8px 14px;
        margin: 0;
        padding: 11px 12px;
        border: 1px solid var(--line);
        border-radius: 9px;
        background: var(--surface-raised);
      }

      .settings-confirmations {
        display: grid;
        gap: 9px;
        padding: 14px;
        border: 1px solid color-mix(in srgb, var(--amber) 45%, var(--line));
        border-radius: var(--radius-sm);
        background: color-mix(in srgb, var(--amber-deep) 34%, var(--surface));
      }

      .settings-confirmations h3 { margin: 0; font-size: 14px; }
      .settings-confirmations p { margin: 0; color: var(--muted); font-size: 12px; }

      .settings-actions {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding: 15px 18px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface);
      }

      .settings-actions p { margin: 0; color: var(--muted); font-size: 12px; }

      .settings-save,
      .rollback-button {
        min-height: 40px;
        padding: 8px 13px;
        border: 1px solid color-mix(in srgb, var(--cyan) 62%, var(--line));
        border-radius: 9px;
        background: var(--cyan-deep);
        color: var(--text);
        cursor: pointer;
        font-size: 13px;
        font-weight: 720;
      }

      .settings-save:hover,
      .rollback-button:hover { border-color: var(--cyan); }

      .settings-history {
        padding: 18px;
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface);
      }

      .revision-list {
        display: grid;
        gap: 9px;
        margin: 0;
        padding: 0;
        list-style: none;
      }

      .revision-item {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: center;
        gap: 14px;
        padding: 12px;
        border: 1px solid var(--line);
        border-radius: var(--radius-sm);
        background: var(--surface-raised);
      }

      .revision-title { display: flex; align-items: baseline; flex-wrap: wrap; gap: 7px; }
      .revision-title strong { font-family: var(--font-mono); font-size: 13px; }
      .revision-title time { color: var(--quiet); font-size: 11px; }
      .revision-copy { margin: 3px 0 0; color: var(--muted); font-size: 12px; }

      .rollback-form {
        display: grid;
        justify-items: end;
        gap: 7px;
        max-width: 290px;
      }

      .rollback-form .settings-check { font-size: 11px; text-align: left; }
      .current-revision { color: var(--green); font-size: 11px; font-weight: 720; }

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
        background: var(--control-disabled);
        color: var(--control-disabled-text);
        cursor: not-allowed;
        font-size: 13px;
        opacity: 1;
      }

      .control-stack {
        display: grid;
        gap: 10px;
      }

      .review-feedback {
        display: flex;
        align-items: baseline;
        justify-content: flex-end;
        gap: 8px;
        color: var(--muted);
        font-size: 13px;
        text-align: right;
      }

      .review-feedback strong { color: var(--text); }
      .review-feedback[data-status="completed"] strong { color: var(--green); }
      .review-feedback[data-status="running"] strong,
      .review-feedback[data-status="queued"] strong { color: var(--amber); }
      .review-feedback[data-status="failed"] strong { color: var(--red); }

      .control-row .run-review-button:not(:disabled) {
        border-color: color-mix(in srgb, var(--cyan) 62%, transparent);
        background: var(--cyan-deep);
        color: var(--text);
        cursor: pointer;
      }

      .control-row .run-review-button:not(:disabled):hover {
        border-color: var(--cyan);
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

      @media (max-width: 960px) {
        .operator-layout { display: block; }
        .operator-sidebar { display: none; }

        .mobile-console-header {
          position: sticky;
          top: 0;
          z-index: 20;
          display: block;
          border-bottom: 1px solid var(--line);
          background: color-mix(in srgb, var(--canvas) 94%, transparent);
          backdrop-filter: blur(14px);
        }

        .mobile-console-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 14px;
          min-height: 58px;
          padding: 9px 14px 7px;
        }

        .mobile-console-top .operator-mark {
          width: 32px;
          height: 32px;
          flex-basis: 32px;
        }

        .mobile-state {
          display: flex;
          min-width: 0;
          align-items: center;
          gap: 8px;
          color: var(--muted);
          font-size: 11px;
        }

        .mobile-state .state-dot {
          width: 8px;
          height: 8px;
          box-shadow: none;
        }

        .mobile-state strong {
          overflow: hidden;
          color: var(--text);
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .mobile-nav-scroll {
          overflow-x: auto;
          padding: 0 10px 9px;
          scrollbar-width: none;
        }

        .mobile-nav-scroll::-webkit-scrollbar { display: none; }

        .mobile-nav-links {
          display: flex;
          width: max-content;
          gap: 4px;
        }

        .mobile-nav-link {
          display: inline-flex;
          align-items: center;
          gap: 7px;
          min-height: 36px;
          padding: 6px 10px;
          border: 1px solid transparent;
          border-radius: 8px;
          color: var(--muted);
          font-size: 12px;
          font-weight: 680;
          text-decoration: none;
          white-space: nowrap;
        }

        .mobile-nav-link.active {
          border-color: color-mix(in srgb, var(--cyan) 32%, var(--line));
          background: var(--cyan-deep);
          color: var(--cyan);
        }

        .dashboard-shell { width: min(100% - 32px, 760px); padding-top: 24px; }
        .page-header { align-items: start; flex-direction: column; gap: 8px; }
        .header-meta { align-items: center; justify-content: space-between; width: 100%; }
        .refresh-note { text-align: left; }
        .status-strip,
        .primary-grid,
        .health-grid,
        .event-grid,
        .about-content,
        .overview-summary-grid,
        .overview-detail-grid,
        .inbox-command-bar,
        .settings-field-grid { grid-template-columns: 1fr; }
        .status-item { border-right: 0; border-bottom: 1px solid var(--line); }
        .status-item:last-child { border-bottom: 0; }
        .planned-controls { grid-template-columns: 1fr; }
        .control-row { justify-content: start; flex-wrap: wrap; }
      }

      @media (max-width: 700px) {
        .setup-card { grid-template-columns: 1fr; gap: 18px; padding: 18px; }
        .setup-steps { grid-template-columns: 1fr; }
        .setup-actions { align-items: stretch; flex-direction: column; }
        .setup-primary { width: 100%; }
      }

      @media (max-width: 520px) {
        .dashboard-shell { width: min(100% - 20px, 480px); }
        .operator-brand-copy span { display: none; }
        .mobile-state > span:not(.state-dot) { display: none; }
        .header-meta { align-items: start; flex-direction: column; }
        .panel { padding: 15px; }
        .image-draft-grid { grid-template-columns: 1fr; }
        .image-preview { height: 220px; }
        .detail-grid { grid-template-columns: 1fr; gap: 9px; }
        .health-counts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .event-title { align-items: start; flex-direction: column; gap: 2px; }
        .overview-schedule-list li { align-items: start; flex-direction: column; gap: 2px; }
        .inbox-category-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .inbox-event-card { grid-template-columns: 1fr; }
        .draft-state-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .draft-review-actions { width: 100%; margin-left: 0; }
        .draft-review-actions button { flex: 1 1 auto; }
        .settings-intro, .settings-actions { align-items: stretch; flex-direction: column; }
        .revision-item { grid-template-columns: 1fr; }
        .rollback-form { justify-items: stretch; max-width: none; }
        .rollback-button { width: 100%; }
        .control-row { display: grid; grid-template-columns: 1fr; }
        .control-row button { width: 100%; }
      }

      @media (prefers-reduced-motion: reduce) {
        *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; }
      }
    </style>

    <aside
      :if={@dashboard_section == :sidebar_navigation}
      id="operator-sidebar"
      class="operator-sidebar"
      aria-label="Operator console"
    >
      <a class="operator-brand" href="/" aria-label="AgentJido operator console home">
        <span class="operator-mark" aria-hidden="true">J</span>
        <span class="operator-brand-copy">
          <strong>AgentJido</strong>
          <span>DelveTown operator</span>
        </span>
      </a>

      <nav class="operator-nav" aria-label="Console views">
        <p class="operator-nav-label">Workspace</p>
        <a
          id="overview-tab"
          class={"operator-nav-link #{tab_class(@active_tab, "overview")}"}
          href="/"
          aria-current={if @active_tab == "overview", do: "page"}
        >
          <span>Overview</span>
        </a>
        <a
          id="inbox-tab"
          class={"operator-nav-link #{tab_class(@active_tab, "inbox")}"}
          href="/?tab=inbox"
          aria-current={if @active_tab == "inbox", do: "page"}
        >
          <span>Inbox</span>
          <span class="nav-count">{inbox_nav_count(@inbox)}</span>
        </a>
        <a
          id="drafts-tab"
          class={"operator-nav-link #{tab_class(@active_tab, "drafts")}"}
          href="/?tab=drafts"
          aria-current={if @active_tab == "drafts", do: "page"}
        >
          <span>Drafts &amp; approvals</span>
          <span class="nav-count">{drafts_nav_count(@drafts)}</span>
        </a>
        <span class="operator-nav-link" aria-disabled="true">
          <span>People</span><span class="nav-soon">Soon</span>
        </span>
        <span class="operator-nav-link" aria-disabled="true">
          <span>Activity</span><span class="nav-soon">Soon</span>
        </span>
        <a
          id="settings-tab"
          class={"operator-nav-link #{tab_class(@active_tab, "settings")}"}
          href="/?tab=settings"
          aria-current={if @active_tab == "settings", do: "page"}
        >
          <span>Settings</span>
        </a>
      </nav>

      <section
        class={"global-agent-state state-#{@operational_state.key}"}
        aria-label="Global agent state"
        aria-live="polite"
      >
        <div class="global-state-heading">
          <span class="state-dot" aria-hidden="true"></span>
          <span class="global-state-copy">
            <span>Agent state</span>
            <strong>{@operational_state.label}</strong>
          </span>
        </div>
        <p class="global-state-effect">{@operational_state.effect}</p>
        <p :if={@operational_state.next} class="global-state-effect">
          Next: {@operational_state.next}
        </p>
        <details :if={@status_error} class="technical-details">
          <summary>Technical details</summary>
          <pre>{@status_error}</pre>
        </details>
        <button
          type="button"
          role="switch"
          aria-checked={to_string(map_value(@status, :writes_enabled?, false))}
          aria-label={write_switch_label(@status)}
          class={"global-write-state #{write_switch_class(@status)}"}
          disabled
        >
          <span>Protocol writes</span>
          <strong>{if map_value(@status, :writes_enabled?, false), do: "ON", else: "OFF"}</strong>
        </button>
      </section>

      <div class="sidebar-meta">
        <span>Local · :{@port}</span>
        <a
          :if={profile_url(@status)}
          href={profile_url(@status)}
          target="_blank"
          rel="noreferrer"
        >
          DelveTown ↗
        </a>
      </div>
    </aside>

    <header
      :if={@dashboard_section == :mobile_navigation}
      id="mobile-console-header"
      class="mobile-console-header"
    >
      <div class="mobile-console-top">
        <a class="operator-brand" href="/" aria-label="AgentJido operator console home">
          <span class="operator-mark" aria-hidden="true">J</span>
          <span class="operator-brand-copy">
            <strong>AgentJido</strong>
            <span>DelveTown operator</span>
          </span>
        </a>
        <div
          class={"mobile-state state-#{@operational_state.key}"}
          aria-label={"Agent state: #{@operational_state.label}"}
          aria-live="polite"
        >
          <span class="state-dot" aria-hidden="true"></span>
          <strong>{@operational_state.label}</strong>
          <span>· writes {if map_value(@status, :writes_enabled?, false), do: "on", else: "off"}</span>
        </div>
      </div>
      <div class="mobile-nav-scroll">
        <nav class="mobile-nav-links" aria-label="Console views">
          <a
            class={"mobile-nav-link #{tab_class(@active_tab, "overview")}"}
            href="/"
            aria-current={if @active_tab == "overview", do: "page"}
          >
            Overview
          </a>
          <a
            class={"mobile-nav-link #{tab_class(@active_tab, "inbox")}"}
            href="/?tab=inbox"
            aria-current={if @active_tab == "inbox", do: "page"}
          >
            Inbox <span class="nav-count">{inbox_nav_count(@inbox)}</span>
          </a>
          <a
            class={"mobile-nav-link #{tab_class(@active_tab, "drafts")}"}
            href="/?tab=drafts"
            aria-current={if @active_tab == "drafts", do: "page"}
          >
            Drafts <span class="nav-count">{drafts_nav_count(@drafts)}</span>
          </a>
          <a
            class={"mobile-nav-link #{tab_class(@active_tab, "settings")}"}
            href="/?tab=settings"
            aria-current={if @active_tab == "settings", do: "page"}
          >
            Settings
          </a>
        </nav>
      </div>
    </header>

    <section
      :if={@dashboard_section == :first_run_setup}
      id="first-run-setup"
      class="setup-page"
      aria-labelledby="setup-title"
    >
      <header class="setup-header">
        <p class="eyebrow">First-run setup</p>
        <h1 id="setup-title">Connect AgentJido</h1>
        <p class="setup-lede">
          Add the local settings that AgentJido needs to read DelveTown and prepare safe proposals.
          Public writes stay off unless you change the mode later.
        </p>
        <ol class="setup-steps" aria-label="Setup steps">
          <li><span>1</span> DelveTown identity</li>
          <li><span>2</span> Decision model</li>
          <li><span>3</span> Safe behavior</li>
        </ol>
      </header>

      <div
        :if={@setup_notice}
        id="setup-notice"
        class={"setup-notice #{@setup_notice.kind}"}
        role="status"
      >
        <strong>{@setup_notice.title}</strong>
        <p>{@setup_notice.text}</p>
        <div class="setup-notice-actions">
          <button
            :if={@setup_notice.kind == "safe"}
            id="open-dashboard"
            type="button"
            class="setup-primary"
            phx-click="open_dashboard"
          >
            Open operator console
          </button>
          <button
            :if={@setup.password_configured? and @setup_notice.kind == "attention"}
            id="retry-setup-connection"
            type="button"
            class="setup-secondary"
            phx-click="test_setup_connection"
            phx-disable-with="Testing…"
          >
            Retry DelveTown connection
          </button>
        </div>
      </div>

      <form id="first-run-form" class="setup-form" phx-submit="save_setup">
        <input
          type="hidden"
          name="setup[settings_version]"
          value={@setup.settings_version}
        />

        <section class="setup-card" aria-labelledby="setup-identity-title">
          <div class="setup-card-copy">
            <p class="panel-kicker">Step 1</p>
            <h2 id="setup-identity-title">DelveTown identity</h2>
            <p>Your app password is encrypted before it is saved in the local SQLite database.</p>
          </div>
          <div class="setup-card-fields">
            <div class="setup-field">
              <label for="setup-identifier">Handle or account identifier</label>
              <input
                id="setup-identifier"
                name="setup[identifier]"
                type="text"
                value={@setup.identifier}
                placeholder="agentjido.delve.town"
                autocomplete="username"
                required
              />
            </div>
            <div class="setup-field">
              <label for="setup-app-password">DelveTown app password</label>
              <input
                id="setup-app-password"
                name="setup[app_password]"
                type="password"
                placeholder="Enter an app password"
                autocomplete="current-password"
                required
              />
              <p class="setup-help">
                The password is never shown again and does not enter settings revision history.
              </p>
            </div>
          </div>
        </section>

        <section class="setup-card" aria-labelledby="setup-model-title">
          <div class="setup-card-copy">
            <p class="panel-kicker">Step 2</p>
            <h2 id="setup-model-title">Decision model</h2>
            <p>The API key stays in the process environment. It is not saved in SQLite.</p>
          </div>
          <div class="setup-card-fields">
            <div class="setup-field">
              <label for="setup-decision-model">Model</label>
              <select id="setup-decision-model" name="setup[decision_model]" required>
                <option
                  :for={option <- @setup.model_options}
                  value={option.value}
                  selected={option.value == @setup.decision_model}
                >
                  {option.label}
                </option>
              </select>
            </div>
            <div class="setup-key-status" aria-label="LLM API key status">
              <div>
                <code>{@setup.llm_key.environment}</code>
                <p>
                  {if @setup.llm_key.configured?,
                    do: "Available to this process",
                    else: "Not detected"}
                </p>
              </div>
              <span class={"badge #{if @setup.llm_key.configured?, do: "healthy", else: "attention"}"}>
                {if @setup.llm_key.configured?, do: "Ready", else: "Missing"}
              </span>
            </div>
          </div>
        </section>

        <section class="setup-card" aria-labelledby="setup-safety-title">
          <div class="setup-card-copy">
            <p class="panel-kicker">Step 3</p>
            <h2 id="setup-safety-title">Safe behavior</h2>
            <p>First-run setup does not offer autonomous mode. You can review that change later.</p>
          </div>
          <div class="setup-card-fields">
            <fieldset class="setup-autonomy">
              <legend>Initial autonomy mode</legend>
              <label :for={option <- @setup.autonomy_options} class="setup-choice">
                <input
                  type="radio"
                  name="setup[autonomy_mode]"
                  value={option.value}
                  checked={option.value == @setup.autonomy_mode}
                />
                <strong>{option.label}</strong>
                <span>{autonomy_help(option.value)}</span>
              </label>
            </fieldset>
          </div>
        </section>

        <div class="setup-actions">
          <p>
            This action saves the local settings, reconnects the session, and verifies the DelveTown identity. It does not publish anything.
          </p>
          <button
            id="save-and-test-setup"
            type="submit"
            class="setup-primary"
            phx-disable-with="Saving and testing…"
          >
            Save and test connection
          </button>
        </div>
      </form>
    </section>

    <header :if={@dashboard_section == :operational_state} class="page-header">
      <div>
        <p class="eyebrow">Operator console</p>
        <h1 id="page-title">{page_title(@active_tab)}</h1>
      </div>
      <div class="header-meta">
        <form class="theme-control" phx-change="set_theme">
          <label for="console-theme">Theme</label>
          <select id="console-theme" name="theme" aria-label="Console theme">
            <option value="system" selected={@theme == "system"}>System</option>
            <option value="light" selected={@theme == "light"}>Light</option>
            <option value="dark" selected={@theme == "dark"}>Dark</option>
          </select>
        </form>
        <p class="refresh-note">
          Last refresh <time datetime={@refreshed_at}>{@refreshed_label}</time> · every 3s
        </p>
      </div>
    </header>

    <section
      :if={@dashboard_section == :runtime_health}
      class="status-strip"
      aria-label="Agent status"
    >
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

    <nav
      :if={@dashboard_section == :runtime_health}
      class="delve-links"
      aria-label="Open AgentJido in DelveTown"
    >
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

    <section
      :if={@dashboard_section == :overview and @active_tab == "overview"}
      id="overview-panel"
      class="overview-stack"
      role="tabpanel"
      aria-labelledby="overview-tab"
    >
      <div class="overview-summary-grid" aria-label="Current operating state">
        <article class="panel overview-summary-card">
          <div class="panel-header">
            <p class="panel-kicker">Autonomy</p>
            <span class={"badge #{map_value(overview_autonomy(@overview), :state, "attention")}"}>
              {display(map_value(overview_autonomy(@overview), :mode))}
            </span>
          </div>
          <p class="overview-value">{display(map_value(overview_autonomy(@overview), :label))}</p>
          <p class="overview-detail">{display(map_value(overview_autonomy(@overview), :detail))}</p>
        </article>

        <article class="panel overview-summary-card">
          <div class="panel-header">
            <p class="panel-kicker">Connection</p>
            <span class={"badge #{map_value(overview_connection(@overview), :state, "attention")}"}>
              {display(map_value(overview_connection(@overview), :label))}
            </span>
          </div>
          <p class="overview-value">
            {if map_value(overview_connection(@overview), :connected?, false),
              do: "Online",
              else: "Standby"}
          </p>
          <p class="overview-detail">{display(map_value(overview_connection(@overview), :detail))}</p>
        </article>

        <article class="panel overview-summary-card">
          <div class="panel-header">
            <p class="panel-kicker">Next scheduled work</p>
            <span class={"badge #{if overview_schedule_enabled?(@overview), do: "healthy", else: "attention"}"}>
              {if overview_schedule_enabled?(@overview), do: "Running", else: "Stopped"}
            </span>
          </div>
          <p :if={overview_schedule_items(@overview) == []} class="overview-detail">
            No valid schedule is available.
          </p>
          <ol :if={overview_schedule_items(@overview) != []} class="overview-schedule-list">
            <li :for={item <- overview_schedule_items(@overview)}>
              <strong>{display(map_value(item, :label))}</strong>
              <time datetime={map_value(item, :next_at_iso8601)}>
                {display(map_value(item, :relative))}
              </time>
            </li>
          </ol>
        </article>
      </div>

      <div class="overview-detail-grid">
        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">Operator queue</p>
              <h2>Needs attention</h2>
            </div>
            <span class={"badge #{if overview_attention(@overview) == [], do: "healthy", else: "attention"}"}>
              {length(overview_attention(@overview))}
            </span>
          </div>
          <p :if={overview_attention(@overview) == []} class="empty">
            Nothing needs operator action.
          </p>
          <ol :if={overview_attention(@overview) != []} class="overview-attention-list">
            <li
              :for={item <- overview_attention(@overview)}
              class={"overview-attention-item #{map_value(item, :state, "attention")}"}
            >
              <strong>{display(map_value(item, :label))}</strong>
              <p>{display(map_value(item, :detail))}</p>
            </li>
          </ol>
        </article>

        <article class="panel">
          <div class="panel-header">
            <div>
              <p class="panel-kicker">Daily limits</p>
              <h2>Participation budget</h2>
            </div>
            <span class="badge safe">SQLite</span>
          </div>
          <ul class="overview-budget-list">
            <li :for={budget <- overview_budgets(@overview)}>
              <div class="overview-budget-heading">
                <strong>{display(map_value(budget, :label))}</strong>
                <span>
                  {display(map_value(budget, :used, 0))} / {display(map_value(budget, :limit, 0))}
                </span>
              </div>
              <div
                class="overview-budget-track"
                role="progressbar"
                aria-label={map_value(budget, :label)}
                aria-valuemin="0"
                aria-valuenow={map_value(budget, :used, 0)}
                aria-valuemax={max(map_value(budget, :limit, 0), 1)}
                style={"--budget-use: #{map_value(budget, :percent, 0)}%"}
              >
                <span></span>
              </div>
            </li>
          </ul>
        </article>
      </div>

      <article class="panel overview-actions">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Audit trail</p>
            <h2>Recent actions</h2>
          </div>
          <span class="count">{length(overview_recent_actions(@overview))} shown</span>
        </div>
        <p :if={overview_recent_actions(@overview) == []} class="empty">
          No participation action is recorded yet.
        </p>
        <ol :if={overview_recent_actions(@overview) != []} class="event-list">
          <li :for={action <- overview_recent_actions(@overview)} class="event-item">
            <div class="event-title">
              <strong>{display(map_value(action, :label))}</strong>
              <span class={"badge #{action_status_class(map_value(action, :status))}"}>
                {state_label(map_value(action, :status, "recorded"))}
              </span>
            </div>
            <p class="event-data">{display(map_value(action, :detail))}</p>
            <time datetime={map_value(action, :at)}>{display(map_value(action, :at))}</time>
          </li>
        </ol>
      </article>

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
    </section>

    <section
      :if={@dashboard_section == :inbox and @active_tab == "inbox"}
      id="inbox-panel"
      class="inbox-shell"
      role="tabpanel"
      aria-labelledby="inbox-tab"
    >
      <article class="panel">
        <div class="inbox-command-bar">
          <div class="inbox-command-copy">
            <p class="panel-kicker">SQLite event queue</p>
            <h2>Participation inbox</h2>
            <p>
              Review replies, mentions, follows, and likes with their local processing state.
              A manual scan uses the normal Oban queue and current safety settings. It does not
              enable protocol writes.
            </p>
            <div class="inbox-category-grid" aria-label="Visible inbox event types">
              <div :for={category <- inbox_categories(@inbox)} class="inbox-category">
                <span>{display(map_value(category, :label))}</span>
                <strong>{display(map_value(category, :count, 0))}</strong>
              </div>
            </div>
          </div>

          <div class="inbox-scan-control">
            <div
              id="reactive-review-feedback"
              class="review-feedback"
              data-status={map_value(@reactive_review, :status)}
              aria-live="polite"
            >
              <strong>{display(map_value(@reactive_review, :label))}</strong>
              <span>{display(map_value(@reactive_review, :detail))}</span>
            </div>
            <button
              id="run-reactive-review"
              type="button"
              class="run-review-button"
              phx-click="run_reactive_review"
              phx-disable-with="Queuing scan…"
              disabled={map_value(@reactive_review, :disabled?, true)}
            >
              Scan DelveTown now
            </button>
            <p class="inbox-scan-meta">{inbox_scan_label(@inbox)}</p>
          </div>
        </div>
      </article>

      <article class="panel">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Processing state</p>
            <h2>Recent social events</h2>
          </div>
          <div class="inbox-panel-meta">
            <span class="count">{inbox_proposal_label(@inbox)}</span>
            <span class={"badge #{if inbox_actionable_count(@inbox) > 0, do: "attention", else: "healthy"}"}>
              {inbox_actionable_count(@inbox)} need attention
            </span>
          </div>
        </div>

        <p :if={inbox_events(@inbox) == []} class="empty">
          No reply, mention, follow, or like event is stored yet. Run a scan to check DelveTown.
        </p>

        <ol :if={inbox_events(@inbox) != []} class="inbox-event-list">
          <li :for={event <- inbox_events(@inbox)} class="inbox-event-card">
            <div class="inbox-event-identity">
              <div class="inbox-event-kind">
                <span class="badge idle">{state_label(map_value(event, :kind))}</span>
                <span class={"badge #{action_status_class(map_value(event, :state))}"}>
                  {state_label(map_value(event, :state))}
                </span>
              </div>
              <strong>{inbox_actor_label(event)}</strong>
              <time datetime={inbox_event_time(event)}>{inbox_time_label(inbox_event_time(event))}</time>
            </div>

            <div class="inbox-event-body">
              <div :if={is_map(map_value(event, :proposal))} class="inbox-proposal">
                <div class="inbox-proposal-heading">
                  <strong>
                    Proposed {state_label(
                      map_value(map_value(event, :proposal, %{}), :action, "action")
                    )}
                  </strong>
                  <span class="badge active">
                    {state_label(map_value(map_value(event, :proposal, %{}), :status, "recorded"))}
                  </span>
                </div>
                <blockquote :if={present_text?(map_value(map_value(event, :proposal, %{}), :text))}>
                  {map_value(map_value(event, :proposal, %{}), :text)}
                </blockquote>
                <p :if={present_text?(map_value(map_value(event, :proposal, %{}), :reason))}>
                  {map_value(map_value(event, :proposal, %{}), :reason)}
                </p>
              </div>
              <p :if={not is_map(map_value(event, :proposal))}>{inbox_event_detail(event)}</p>
              <a
                :if={post_url(map_value(event, :record_uri))}
                class="inbox-source-link"
                href={post_url(map_value(event, :record_uri))}
                target="_blank"
                rel="noreferrer"
              >
                View source post ↗
              </a>
            </div>
          </li>
        </ol>
      </article>
    </section>

    <section
      :if={@dashboard_section == :memory_and_effects and @active_tab == "overview"}
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
      :if={@dashboard_section == :scan_and_database_status and @active_tab == "overview"}
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

    <section
      :if={@dashboard_section == :recent_events and @active_tab == "overview"}
      class="event-grid"
      aria-label="Recent events"
    >
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
      :if={@dashboard_section == :planned_controls and @active_tab == "overview"}
      class="planned-controls"
      aria-label="Manual controls"
    >
      <div>
        <h2>Manual controls</h2>
        <p>Start a timeline review with the current dry-run and safety settings.</p>
      </div>
      <div class="control-stack">
        <div
          id="proactive-review-feedback"
          class="review-feedback"
          data-status={map_value(@proactive_review, :status)}
          aria-live="polite"
        >
          <strong>{map_value(@proactive_review, :label)}</strong>
          <span>{map_value(@proactive_review, :detail)}</span>
        </div>
        <div class="control-row">
          <button
            id="run-proactive-review"
            type="button"
            class="run-review-button"
            phx-click="run_proactive_review"
            phx-disable-with="Queuing review…"
            disabled={map_value(@proactive_review, :disabled?, true)}
          >
            Run proactive review
          </button>
        </div>
      </div>
    </section>

    <details
      :if={@dashboard_section == :agent_information and @active_tab == "overview"}
      class="about-panel"
    >
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
      :if={@dashboard_section == :drafts and @active_tab == "drafts"}
      id="drafts-panel"
      class="drafts-shell"
      role="tabpanel"
      aria-labelledby="drafts-tab"
    >
      <article class="panel drafts-summary">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Local review queue</p>
            <h2>Drafts and approvals</h2>
          </div>
          <span class={"badge #{if @manual_publish_enabled, do: "safe", else: "idle"}"}>
            {if @manual_publish_enabled, do: "Manual publish ready", else: "Publishing locked"}
          </span>
        </div>

        <p class="simulated-intro">
          Review text, like, and image proposals in one place. Approval and rejection are local
          SQLite decisions. They do not publish, upload, or change DelveTown. Publication needs a
          separate confirmed action and the manual publish permission.
        </p>

        <div class="draft-state-grid" aria-label="Draft review counts">
          <div><strong>{draft_count(@drafts, :pending_count)}</strong><span>Pending</span></div>
          <div><strong>{draft_count(@drafts, :approved_count)}</strong><span>Approved</span></div>
          <div><strong>{draft_count(@drafts, :rejected_count)}</strong><span>Rejected</span></div>
          <div><strong>{draft_count(@drafts, :published_count)}</strong><span>Published</span></div>
        </div>

        <p
          :if={@draft_review_notice}
          class={"publish-notice #{map_value(@draft_review_notice, :kind)}"}
          role="status"
        >
          {map_value(@draft_review_notice, :text)}
        </p>
      </article>

      <article class="panel draft-section" aria-labelledby="text-drafts-heading">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">DelveTown post preview</p>
            <h2 id="text-drafts-heading">Posts and replies</h2>
          </div>
          <span class="count">{draft_type_count(@drafts, :text)}</span>
        </div>

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
          No post or reply draft is waiting for review.
        </p>

        <ol :if={inspection_list(@inspection, [:simulated_posts]) != []} class="simulated-list">
          <li
            :for={post <- inspection_list(@inspection, [:simulated_posts])}
            class="simulated-card draft-card"
          >
            <div class="simulated-card-header">
              <span class={"badge #{draft_state_class(text_draft_state(post))}"}>
                {state_label(text_draft_state(post))}
              </span>
              <time>{draft_time(post, :simulated_at)}</time>
            </div>
            <div class="social-preview-author">
              <span class="social-avatar" aria-hidden="true">J</span>
              <span><strong>AgentJido</strong><small>@{session_actor(@status) || "local draft"}</small></span>
            </div>
            <blockquote class="simulated-draft">{simulated_text(post)}</blockquote>
            <div class="simulated-meta">
              <span><strong>Type:</strong> {state_label(map_value(post, :action, "post"))}</span>
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
              <div :if={not published?(post)} class="draft-review-actions">
                <button
                  :if={draft_review_state(post) != "approved"}
                  type="button"
                  class="review-button approve"
                  phx-click="review_draft"
                  phx-value-kind="text"
                  phx-value-source_key={map_value(post, :event_key)}
                  phx-value-decision="approved"
                  phx-disable-with="Saving…"
                >
                  Approve
                </button>
                <button
                  :if={draft_review_state(post) != "rejected"}
                  type="button"
                  class="review-button reject"
                  phx-click="review_draft"
                  phx-value-kind="text"
                  phx-value-source_key={map_value(post, :event_key)}
                  phx-value-decision="rejected"
                  phx-disable-with="Saving…"
                >
                  Reject
                </button>
                <button
                  :if={draft_review_state(post) == "approved"}
                  type="button"
                  class="publish-button"
                  phx-click="publish_simulated"
                  phx-value-event_key={map_value(post, :event_key)}
                  phx-disable-with="Publishing…"
                  data-confirm="Publish this exact approved draft to DelveTown?"
                  disabled={not @manual_publish_enabled}
                >
                  Publish to DelveTown
                </button>
              </div>
            </div>
          </li>
        </ol>
      </article>

      <article id="like-proposals" class="panel draft-section" aria-labelledby="like-drafts-heading">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Target post preview</p>
            <h2 id="like-drafts-heading">Like proposals</h2>
          </div>
          <span class="count">{draft_type_count(@drafts, :like)}</span>
        </div>

        <p
          :if={@like_publish_notice}
          class={"publish-notice #{map_value(@like_publish_notice, :kind)}"}
          role="status"
        >
          {map_value(@like_publish_notice, :text)}
          <a
            :if={post_url(map_value(@like_publish_notice, :uri))}
            href={post_url(map_value(@like_publish_notice, :uri))}
            target="_blank"
            rel="noreferrer"
          >
            View target post ↗
          </a>
        </p>

        <p :if={inspection_list(@inspection, [:like_proposals]) == []} class="empty">
          No like proposal is waiting for review.
        </p>

        <ol :if={inspection_list(@inspection, [:like_proposals]) != []} class="simulated-list">
          <li
            :for={proposal <- inspection_list(@inspection, [:like_proposals])}
            class="simulated-card draft-card"
          >
            <div class="simulated-card-header">
              <span class={"badge #{draft_state_class(like_draft_state(proposal))}"}>
                {state_label(like_draft_state(proposal))}
              </span>
              <time>{draft_time(proposal, :selected_at)}</time>
            </div>
            <div class="social-preview-author">
              <span class="social-avatar muted" aria-hidden="true">@</span>
              <span><strong>{like_author_label(proposal)}</strong><small>DelveTown post</small></span>
            </div>
            <blockquote class="simulated-draft">{like_post_text(proposal)}</blockquote>
            <div class="simulated-meta">
              <span><strong>Selection:</strong> {display(map_value(proposal, :selection_reason))}</span>
              <span><strong>Policy score:</strong> {display(map_value(proposal, :policy_score))}</span>
              <span><strong>Budget:</strong> {like_budget_label(proposal)}</span>
              <span><strong>Event:</strong> {state_label(map_value(proposal, :event_state))}</span>
            </div>
            <div class="simulated-actions">
              <a
                :if={post_url(map_value(proposal, :target_uri))}
                class="source-link"
                href={post_url(map_value(proposal, :target_uri))}
                target="_blank"
                rel="noreferrer"
              >
                View target post ↗
              </a>
              <span :if={like_published?(proposal)} class="published-state">Published</span>
              <div :if={like_reviewable?(proposal)} class="draft-review-actions">
                <button
                  :if={draft_review_state(proposal) != "approved"}
                  type="button"
                  class="review-button approve"
                  phx-click="review_draft"
                  phx-value-kind="like"
                  phx-value-source_key={map_value(proposal, :event_key)}
                  phx-value-decision="approved"
                  phx-disable-with="Saving…"
                >
                  Approve
                </button>
                <button
                  :if={draft_review_state(proposal) != "rejected"}
                  type="button"
                  class="review-button reject"
                  phx-click="review_draft"
                  phx-value-kind="like"
                  phx-value-source_key={map_value(proposal, :event_key)}
                  phx-value-decision="rejected"
                  phx-disable-with="Saving…"
                >
                  Reject
                </button>
                <button
                  :if={draft_review_state(proposal) == "approved"}
                  type="button"
                  class="publish-button"
                  phx-click="publish_simulated_like"
                  phx-value-event_key={map_value(proposal, :event_key)}
                  phx-disable-with="Publishing…"
                  data-confirm="Publish this exact approved like to DelveTown?"
                  disabled={not @manual_publish_enabled}
                >
                  Publish like to DelveTown
                </button>
              </div>
            </div>
          </li>
        </ol>
      </article>

      <article class="panel draft-section" aria-labelledby="image-drafts-heading">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Image post preview</p>
            <h2 id="image-drafts-heading">Image posts</h2>
          </div>
          <span class="count">{draft_type_count(@drafts, :image)}</span>
        </div>

        <p
          :if={@image_publish_notice}
          class={"publish-notice #{map_value(@image_publish_notice, :kind)}"}
          role="status"
        >
          {map_value(@image_publish_notice, :text)}
          <a
            :if={post_url(map_value(@image_publish_notice, :uri), session_actor(@status))}
            href={post_url(map_value(@image_publish_notice, :uri), session_actor(@status))}
            target="_blank"
            rel="noreferrer"
          >
            View published post ↗
          </a>
        </p>

        <p :if={inspection_list(@inspection, [:image_drafts]) == []} class="empty">
          No image post is waiting for review.
        </p>

        <ol :if={inspection_list(@inspection, [:image_drafts]) != []} class="image-draft-grid">
          <li
            :for={draft <- inspection_list(@inspection, [:image_drafts])}
            class="image-draft-card draft-card"
          >
            <img
              class="image-preview"
              src={inspection_value(draft, [:artifact, :preview_data_url])}
              alt={map_value(draft, :alt_text, "Image draft preview")}
            />
            <div class="image-draft-body">
              <div class="simulated-card-header">
                <span class={"badge #{draft_state_class(image_draft_state(draft))}"}>
                  {state_label(image_draft_state(draft))}
                </span>
                <time>{draft_time(draft, :inserted_at)}</time>
              </div>
              <div class="social-preview-author">
                <span class="social-avatar" aria-hidden="true">J</span>
                <span><strong>AgentJido</strong><small>Image post</small></span>
              </div>
              <p class="image-caption">{display(map_value(draft, :caption))}</p>
              <p class="image-alt">
                <strong>Alt text:</strong> {display(map_value(draft, :alt_text))}
              </p>

              <div class="image-state-grid" aria-label="Image draft states">
                <div class="image-state">
                  <span>Validation</span><strong>{state_label(map_value(draft, :validation_state))}</strong>
                </div>
                <div class="image-state">
                  <span>Upload</span><strong>{state_label(
                    inspection_value(draft, [:artifact, :upload_state])
                  )}</strong>
                </div>
                <div class="image-state">
                  <span>Publication</span><strong>{state_label(map_value(draft, :publication_state))}</strong>
                </div>
              </div>
              <p class="image-file-meta">{image_file_detail(draft)}</p>

              <div class="simulated-actions">
                <a
                  :if={image_post_url(draft, @status)}
                  class="source-link"
                  href={image_post_url(draft, @status)}
                  target="_blank"
                  rel="noreferrer"
                >
                  View published post ↗
                </a>
                <span :if={image_published?(draft)} class="published-state">Published</span>
                <div :if={not image_published?(draft)} class="draft-review-actions">
                  <button
                    :if={draft_review_state(draft) != "approved"}
                    type="button"
                    class="review-button approve"
                    phx-click="review_draft"
                    phx-value-kind="image"
                    phx-value-source_key={map_value(draft, :draft_key)}
                    phx-value-decision="approved"
                    phx-disable-with="Saving…"
                  >
                    Approve
                  </button>
                  <button
                    :if={draft_review_state(draft) != "rejected"}
                    type="button"
                    class="review-button reject"
                    phx-click="review_draft"
                    phx-value-kind="image"
                    phx-value-source_key={map_value(draft, :draft_key)}
                    phx-value-decision="rejected"
                    phx-disable-with="Saving…"
                  >
                    Reject
                  </button>
                  <button
                    :if={draft_review_state(draft) == "approved"}
                    type="button"
                    class="publish-button"
                    phx-click="publish_image"
                    phx-value-draft_key={map_value(draft, :draft_key)}
                    phx-disable-with="Publishing…"
                    data-confirm="Upload and publish this exact approved image to DelveTown?"
                    disabled={not @manual_publish_enabled}
                  >
                    Publish image to DelveTown
                  </button>
                </div>
              </div>
            </div>
          </li>
        </ol>
      </article>
    </section>

    <section
      :if={@dashboard_section == :settings and @active_tab == "settings"}
      id="settings-panel"
      class="settings-shell"
      role="tabpanel"
      aria-labelledby="settings-tab"
    >
      <article class="panel settings-intro">
        <div>
          <p class="panel-kicker">SQLite runtime configuration</p>
          <h2>Runtime settings</h2>
          <p class="proposal-copy">
            Changes are validated and saved as an immutable revision. Each field shows when its
            value becomes active. App passwords stay encrypted and do not appear in history.
          </p>
        </div>
        <span :if={map_value(@settings_editor, :version)} class="settings-version">
          version {map_value(@settings_editor, :version)} · schema {map_value(
            @settings_editor,
            :schema_version
          )}
        </span>
      </article>

      <p
        :if={@settings_notice}
        class={"publish-notice #{map_value(@settings_notice, :kind)}"}
        role="status"
      >
        <strong>{map_value(@settings_notice, :title)}</strong><br />
        {map_value(@settings_notice, :text)}
      </p>

      <article :if={not map_value(@settings_editor, :available?, false)} class="panel">
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Settings unavailable</p>
            <h2>The settings store could not be read</h2>
          </div>
          <span class="badge attention">Needs attention</span>
        </div>
        <p class="proposal-copy">Check the SQLite database and the local logs.</p>
        <details class="technical-details">
          <summary>Technical details</summary>
          <pre>{map_value(@settings_editor, :error)}</pre>
        </details>
      </article>

      <form
        :if={map_value(@settings_editor, :available?, false)}
        id="runtime-settings-form"
        class="settings-form"
        phx-submit="save_settings"
      >
        <input
          type="hidden"
          name="settings[version]"
          value={map_value(@settings_editor, :version)}
        />

        <article
          :for={section <- settings_sections(@settings_editor)}
          class="settings-section"
          data-section={map_value(section, :key)}
          aria-labelledby={"settings-#{map_value(section, :key)}-heading"}
        >
          <div class="settings-section-heading">
            <h2 id={"settings-#{map_value(section, :key)}-heading"}>
              {map_value(section, :label)}
            </h2>
            <p>{map_value(section, :description)}</p>
          </div>

          <div class="settings-field-grid">
            <div
              :for={field <- settings_fields(section)}
              class={settings_field_class(field)}
            >
              <%= case map_value(field, :input) do %>
                <% :checkbox -> %>
                  <div class="settings-label-row">
                    <span class="settings-legend">{map_value(field, :label)}</span>
                    <span class="activation-chip">{map_value(field, :activation_label)}</span>
                  </div>
                  <input
                    type="hidden"
                    name={settings_input_name(field)}
                    value="false"
                  />
                  <label class="settings-check" for={map_value(field, :id)}>
                    <input
                      id={map_value(field, :id)}
                      type="checkbox"
                      name={settings_input_name(field)}
                      value="true"
                      checked={map_value(field, :checked?, false)}
                    />
                    <span>{map_value(field, :help)}</span>
                  </label>
                <% :checkboxes -> %>
                  <div class="settings-label-row">
                    <span id={"#{map_value(field, :id)}-label"} class="settings-legend">
                      {map_value(field, :label)}
                    </span>
                    <span class="activation-chip">{map_value(field, :activation_label)}</span>
                  </div>
                  <fieldset
                    class="settings-options"
                    aria-labelledby={"#{map_value(field, :id)}-label"}
                  >
                    <label :for={option <- map_value(field, :options, [])} class="settings-option">
                      <input
                        type="checkbox"
                        name={"#{settings_input_name(field)}[]"}
                        value={map_value(option, :value)}
                        checked={map_value(option, :value) in map_value(field, :selected, [])}
                      />
                      <span>{map_value(option, :label)}</span>
                    </label>
                  </fieldset>
                  <p :if={map_value(field, :validation)} class="settings-help">
                    {map_value(field, :validation)}
                  </p>
                <% :select -> %>
                  <div class="settings-label-row">
                    <label for={map_value(field, :id)}>{map_value(field, :label)}</label>
                    <span class="activation-chip">{map_value(field, :activation_label)}</span>
                  </div>
                  <select
                    id={map_value(field, :id)}
                    name={settings_input_name(field)}
                  >
                    <option
                      :for={option <- map_value(field, :options, [])}
                      value={map_value(option, :value)}
                      selected={map_value(option, :value) == map_value(field, :value)}
                    >
                      {map_value(option, :label)}
                    </option>
                  </select>
                  <p :if={map_value(field, :help)} class="settings-help">
                    {map_value(field, :help)}
                  </p>
                <% input -> %>
                  <div class="settings-label-row">
                    <label for={map_value(field, :id)}>{map_value(field, :label)}</label>
                    <span class="activation-chip">{map_value(field, :activation_label)}</span>
                  </div>
                  <input
                    id={map_value(field, :id)}
                    type={settings_html_input_type(input)}
                    name={settings_input_name(field)}
                    value={map_value(field, :value)}
                    min={map_value(field, :min)}
                    max={map_value(field, :max)}
                    autocomplete={settings_autocomplete(field)}
                    placeholder={settings_placeholder(field)}
                  />
                  <p :if={map_value(field, :help)} class="settings-help">
                    {map_value(field, :help)}
                  </p>
                  <p :if={map_value(field, :validation)} class="settings-help">
                    {map_value(field, :validation)}
                  </p>
              <% end %>
            </div>
          </div>
        </article>

        <article class="settings-confirmations" aria-labelledby="protected-settings-heading">
          <h3 id="protected-settings-heading">Protected changes</h3>
          <p>These checks apply only if the matching protected value is selected.</p>
          <label class="settings-check" for="confirm-autonomous">
            <input
              id="confirm-autonomous"
              type="checkbox"
              name="settings[confirm_autonomous]"
              value="true"
            />
            <span>I confirm that autonomous mode can create public DelveTown effects.</span>
          </label>
          <label class="settings-check" for="confirm-notifications">
            <input
              id="confirm-notifications"
              type="checkbox"
              name="settings[confirm_notifications]"
              value="true"
            />
            <span>I confirm that marking notifications as seen is a remote protocol write.</span>
          </label>
        </article>

        <div class="settings-actions">
          <p>
            Save creates one local revision. It does not test the connection or publish content.
          </p>
          <button
            id="save-runtime-settings"
            type="submit"
            class="settings-save"
            phx-disable-with="Saving settings…"
          >
            Save settings
          </button>
        </div>
      </form>

      <article
        :if={map_value(@settings_editor, :available?, false)}
        class="settings-history"
        aria-labelledby="settings-history-heading"
      >
        <div class="panel-header">
          <div>
            <p class="panel-kicker">Immutable local record</p>
            <h2 id="settings-history-heading">Revision history</h2>
          </div>
          <span class="count">{length(settings_history(@settings_editor))} recent</span>
        </div>
        <p :if={settings_history(@settings_editor) == []} class="empty">
          No settings revisions are available.
        </p>
        <ol :if={settings_history(@settings_editor) != []} class="revision-list">
          <li :for={revision <- settings_history(@settings_editor)} class="revision-item">
            <div>
              <div class="revision-title">
                <strong>v{map_value(revision, :version)}</strong>
                <span>{map_value(revision, :source)}</span>
                <time datetime={map_value(revision, :inserted_at)}>
                  {map_value(revision, :inserted_label)}
                </time>
              </div>
              <p class="revision-copy">{Enum.join(map_value(revision, :changed, []), " · ")}</p>
            </div>

            <span :if={map_value(revision, :current?, false)} class="current-revision">
              Current version
            </span>

            <form
              :if={not map_value(revision, :current?, false)}
              class="rollback-form"
              phx-submit="rollback_settings"
            >
              <input
                type="hidden"
                name="target_version"
                value={map_value(revision, :version)}
              />
              <input
                type="hidden"
                name="rollback[version]"
                value={map_value(@settings_editor, :version)}
              />
              <label
                :if={map_value(revision, :confirms_autonomous?, false)}
                class="settings-check"
              >
                <input type="checkbox" name="rollback[confirm_autonomous]" value="true" />
                <span>Confirm autonomous mode</span>
              </label>
              <label
                :if={map_value(revision, :confirms_notifications?, false)}
                class="settings-check"
              >
                <input type="checkbox" name="rollback[confirm_notifications]" value="true" />
                <span>Confirm remote notification writes</span>
              </label>
              <button
                type="submit"
                class="rollback-button"
                data-confirm={"Restore recorded values from version #{map_value(revision, :version)}? The current app password will stay unchanged."}
                phx-disable-with="Rolling back…"
              >
                Roll back to v{map_value(revision, :version)}
              </button>
            </form>
          </li>
        </ol>
      </article>
    </section>

    <p :if={@dashboard_section == :footer} class="footer-note">
      Local dashboard on port {@port}. Scheduled protocol writes remain controlled by the write lock.
    </p>
    """
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

  defp overview_autonomy(overview), do: map_value(overview, :autonomy, %{})
  defp overview_connection(overview), do: map_value(overview, :connection, %{})
  defp overview_attention(overview), do: inspection_list(overview, [:attention])
  defp overview_budgets(overview), do: inspection_list(overview, [:budgets])

  defp overview_schedule_items(overview),
    do: inspection_list(overview, [:schedule, :items])

  defp overview_schedule_enabled?(overview),
    do: inspection_value(overview, [:schedule, :enabled?], false)

  defp overview_recent_actions(overview),
    do: inspection_list(overview, [:recent_actions])

  defp inbox_events(inbox), do: inspection_list(inbox, [:events])
  defp inbox_categories(inbox), do: inspection_list(inbox, [:categories])

  defp inbox_actionable_count(inbox) do
    case map_value(inbox, :actionable_count, 0) do
      count when is_integer(count) and count >= 0 -> count
      _count -> 0
    end
  end

  defp inbox_nav_count(inbox), do: inbox_actionable_count(inbox)

  defp drafts_nav_count(drafts), do: draft_count(drafts, :pending_count)

  defp draft_count(drafts, key) do
    case map_value(drafts, key, 0) do
      count when is_integer(count) and count >= 0 -> count
      _count -> 0
    end
  end

  defp draft_type_count(drafts, kind) do
    drafts
    |> map_value(:type_counts, %{})
    |> draft_count(kind)
  end

  defp settings_sections(settings), do: inspection_list(settings, [:sections])
  defp settings_fields(section), do: inspection_list(section, [:fields])
  defp settings_history(settings), do: inspection_list(settings, [:history])

  defp settings_field_class(field) do
    if map_value(field, :input) == :checkboxes,
      do: "settings-field full",
      else: "settings-field"
  end

  defp settings_input_name(field), do: "settings[#{map_value(field, :name)}]"

  defp settings_html_input_type(:password), do: "password"
  defp settings_html_input_type(:number), do: "number"
  defp settings_html_input_type(_input), do: "text"

  defp settings_autocomplete(field) do
    case map_value(field, :key) do
      :account_identifier -> "username"
      :account_app_password -> "new-password"
      _key -> nil
    end
  end

  defp settings_placeholder(field) do
    if map_value(field, :secret_stored?, false), do: "Stored; leave blank to keep", else: nil
  end

  defp inbox_proposal_label(inbox) do
    count =
      case map_value(inbox, :proposal_count, 0) do
        value when is_integer(value) and value >= 0 -> value
        _value -> 0
      end

    if count == 1, do: "1 proposal", else: "#{count} proposals"
  end

  defp inbox_scan_label(inbox) do
    case map_value(inbox, :last_scan) do
      scan when is_map(scan) ->
        if map_value(scan, :lease_active?, false) do
          "A notification scan is running."
        else
          "Last completed scan: #{inbox_time_label(map_value(scan, :last_completed_at))}"
        end

      _scan ->
        "No completed notification scan is recorded."
    end
  end

  defp inbox_actor_label(event) do
    actor = map_value(event, :actor, %{})

    cond do
      present_text?(map_value(actor, :handle)) -> "@#{map_value(actor, :handle)}"
      present_text?(map_value(actor, :display_name)) -> map_value(actor, :display_name)
      present_text?(map_value(actor, :did)) -> map_value(actor, :did)
      true -> "Unknown actor"
    end
  end

  defp inbox_event_time(event) do
    map_value(event, :terminal_at) || map_value(event, :claimed_at) ||
      map_value(event, :occurred_at) || map_value(event, :updated_at)
  end

  defp inbox_time_label(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> Calendar.strftime(time, "%b %d · %H:%M UTC")
      _error -> display(value)
    end
  end

  defp inbox_time_label(value), do: display(value)

  defp inbox_event_detail(event) do
    case map_value(event, :state) do
      "pending" -> "Waiting for the next reactive review."
      "claimed" -> "The reactive worker is processing this event."
      "completed" -> "Processing completed without a saved proposal."
      "ignored" -> "The active policy ignored this event."
      "failed" -> "Processing failed. Check the local logs before another scan."
      _state -> "The local processing state is unavailable."
    end
  end

  defp present_text?(value), do: is_binary(value) and String.trim(value) != ""

  defp draft_review_state(item) do
    item
    |> map_value(:review, %{})
    |> map_value(:state, "pending")
  end

  defp text_draft_state(post) do
    if published?(post), do: "published", else: draft_review_state(post)
  end

  defp like_draft_state(proposal) do
    case map_value(proposal, :publication_state) do
      state when state in ["published", "failed", "ignored"] -> state
      _state -> draft_review_state(proposal)
    end
  end

  defp image_draft_state(draft) do
    if image_published?(draft), do: "published", else: draft_review_state(draft)
  end

  defp draft_state_class("approved"), do: "safe"
  defp draft_state_class("published"), do: "safe"
  defp draft_state_class("rejected"), do: "attention"
  defp draft_state_class("failed"), do: "attention"
  defp draft_state_class("ignored"), do: "attention"
  defp draft_state_class(_state), do: "active"

  defp draft_time(item, key), do: inbox_time_label(map_value(item, key))

  defp action_status_class(status)
       when status in ["ok", :ok, "completed", "published", "acted"],
       do: "safe"

  defp action_status_class(status)
       when status in ["error", :error, "failed", "permanent_failure", "uncertain"],
       do: "attention"

  defp action_status_class(status) when status in ["proposed", "queued", "running"],
    do: "active"

  defp action_status_class(_status), do: "idle"

  defp tab_class(active_tab, tab) when active_tab == tab, do: "active"
  defp tab_class(_active_tab, _tab), do: ""

  defp page_title("inbox"), do: "Participation inbox"
  defp page_title("drafts"), do: "Drafts & approvals"
  defp page_title("settings"), do: "Runtime settings"
  defp page_title(_active_tab), do: "Overview"

  defp autonomy_help("review"),
    do: "Save proposals for approval. No selected action publishes automatically."

  defp autonomy_help(_mode),
    do: "Inspect activity and prepare proposals. All protocol effects stay blocked."

  defp simulated_text(post) do
    case map_value(post, :text) do
      text when is_binary(text) and text != "" -> text
      _text -> "Draft text was not stored for this older simulated action."
    end
  end

  defp like_author_label(proposal) do
    author = map_value(proposal, :target_author, %{})

    case map_value(author, :handle) do
      handle when is_binary(handle) and handle != "" -> "@#{handle}"
      _handle -> display(map_value(author, :display_name) || map_value(author, :did))
    end
  end

  defp like_post_text(proposal) do
    case map_value(proposal, :post_text) do
      text when is_binary(text) and text != "" -> text
      _text -> "Target post text was not stored for this older proposal."
    end
  end

  defp like_budget_label(proposal) do
    budget = map_value(proposal, :budget, %{})

    case {map_value(budget, :likes), map_value(budget, :limit), map_value(budget, :remaining)} do
      {likes, limit, remaining}
      when is_integer(likes) and is_integer(limit) and is_integer(remaining) ->
        "#{likes} of #{limit} used · #{remaining} left"

      _budget ->
        "Not recorded"
    end
  end

  defp like_published?(proposal),
    do: map_value(proposal, :publication_state) == "published"

  defp like_reviewable?(proposal) do
    map_value(proposal, :proposal_status) == "simulated" and
      map_value(proposal, :event_state) == "completed" and not like_published?(proposal)
  end

  defp published?(post), do: map_value(post, :published_status) == "completed"

  defp published_post_url(post, status) do
    post_url(map_value(post, :published_uri), session_actor(status))
  end

  defp image_published?(draft), do: map_value(draft, :publication_state) == "published"

  defp image_post_url(draft, status) do
    post_url(map_value(draft, :post_uri), session_actor(status))
  end

  defp image_file_detail(draft) do
    artifact = map_value(draft, :artifact, %{})
    mime_type = display(map_value(artifact, :mime_type))
    byte_size = display(map_value(artifact, :byte_size))
    dimensions = image_dimensions(artifact)
    digest = display(map_value(artifact, :digest))
    "#{mime_type} · #{byte_size} bytes · #{dimensions} · #{digest}"
  end

  defp image_dimensions(artifact) do
    case {map_value(artifact, :width), map_value(artifact, :height)} do
      {width, height} when is_integer(width) and is_integer(height) -> "#{width}×#{height}"
      _dimensions -> "dimensions not set"
    end
  end

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
