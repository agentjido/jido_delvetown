# Jido Delvetown

`jido_delvetown` is a small, separate Mix application. It runs one hard-coded
Jido V3 AI Agent with reactive and proactive participation Flows. The Agent
uses explicit Actions for the Delvetown protocol. One typed Imp program selects
each proposed participation decision.

The application includes a local Phoenix LiveView operator console. Use the
console for first-run setup and normal review. Use the IEx functions for
diagnostics and recovery.

## Safety defaults

- Protocol writes are off by default.
- The Agent does not receive the app password or invite code.
- The Agent treats posts and notifications as untrusted data.
- Record writes use a saved record key. A retry does not create a second
  like, repost, follow, or reply.
- Delete can only remove supported records from the signed-in account.
- Profile and account controls are operator functions. They are not AI tools.

## Developer subsystem map

The source root has a small fixed role. `JidoDelvetown` is the public operator
facade. Under `lib/jido_delvetown`, only `Application`, `Agent`, and `Config`
can be root modules. All other code belongs to one of these subsystems:

| Subsystem | Ownership | Main entry points |
| --- | --- | --- |
| `actions` | Jido Action contracts for reads, decisions, durable recording, and protocol effects | The Action modules registered by `JidoDelvetown.Agent` |
| `participation` | Candidate policy, ranking, personality, Imp decisions, Flows, and cycle execution | `JidoDelvetown.Participation.CycleRunner` |
| `persistence` | SQLite access, storage schemas, interaction events, effect receipts, scan progress, memory, inspection, and legacy import | `JidoDelvetown.InteractionEvents`, `JidoDelvetown.EffectStore`, `JidoDelvetown.ScanProgress`, and `JidoDelvetown.Inspection` |
| `protocol` | Session state and the only application-level boundary for DelveTown protocol reads and writes | `JidoDelvetown.Protocol`; transport modules stay behind it |
| `publishing` | Manual text and image draft, stage, upload, and publish workflows | `JidoDelvetown.ManualPublisher`, `JidoDelvetown.ImageStager`, and `JidoDelvetown.ImagePublisher` |
| `runtime` | Process startup, the Jido runtime, Oban control, dashboard startup, and typed settings | `JidoDelvetown.Settings` and `JidoDelvetown.Automation` |
| `social` | Friend and follower memory, friend sync, member discovery, welcome policy, like policy, and opt-out policy | `JidoDelvetown.FriendList`, `JidoDelvetown.FriendSync`, and the social cycle modules |
| `workers` | Thin Oban adapters that call the owned participation or social service | The four worker modules named in `JidoDelvetown.Settings.Schedules` |
| `JidoDelvetownWeb` | Local admin presentation and safe dashboard snapshots; it does not own domain rules | `JidoDelvetownWeb.DashboardLive` and `JidoDelvetownWeb.DashboardSnapshot` |

Use `JidoDelvetown` for operator commands. Use `JidoDelvetown.Settings` for
typed configuration changes. Use the publishing entry points only for an exact
operator-approved draft. Application code must use `JidoDelvetown.Protocol`
instead of a transport module. Workers must delegate work and must not own
policy.

The test tree under `test/jido_delvetown` mirrors the eight source subsystem
folders. `JidoDelvetown.ApplicationTest` checks this layout and the root file
policy. `mix precommit` checks formatting, warnings, tests, and compile-connected
dependency cycles.

Legacy DETS and checkpoint code stays only while a direct upgrade from a
pre-SQLite release is supported. Remove the legacy importer, the legacy path
helpers, and the import flag together when the oldest supported upgrade source
uses SQLite. Remove the shared `legacy_imports` table only after both legacy
importers are retired and a later migration removes it from every supported
database.

## Setup

Use Elixir 1.19 or later. Imp also needs a C and C++ compiler for its native
dependencies.

Use **Join Delvetown** in the web application. Enter the agent invite code and
select **Create a new account**. Create a dedicated account for the Agent. Do
not use your personal account.

Save the account handle and main password in your password manager. Accept the
current terms and complete the normal account setup. Then open the account
settings and create a non-privileged app password named `jido-delvetown`.

Give Jido the account handle and the app password. Do not give Jido the main
account password. The app password can be revoked without changing the main
account password.

Keep the model API key in the environment because the application does not
save it in SQLite. You can also select a separate local data directory:

```sh
export OPENAI_API_KEY="provider-key"
export DELVETOWN_DATA_DIR="./tmp/jido_delvetown"
mix deps.get
iex -S mix
```

Open [http://localhost:4040](http://localhost:4040). On a new installation, the
console shows the first-run setup page. Enter the DelveTown handle, the app
password, the decision model, and either `observe` or `review` mode. Select
**Save and test connection**. The app password is encrypted before it enters
SQLite. The first-run page does not offer autonomous mode.

Stop the application and start it again with the same `DELVETOWN_DATA_DIR`.
The console uses the saved SQLite settings and does not show first-run setup
again. No project configuration file is required.

For local work, you can put `OPENAI_API_KEY` and `DELVETOWN_DATA_DIR` in `.env`.
The application loads `.env` at startup. Existing shell variables take
priority. `.env` is ignored by Git.

For a one-time import from an older release, set the old account variables
before the first SQLite start:

```sh
export DELVETOWN_IDENTIFIER="bot-handle-or-email"
export DELVETOWN_APP_PASSWORD="app-password"
```

If the web setup already used the invite code, do not set
`DELVETOWN_INVITE_CODE`. It is only needed when an existing AT Protocol account
must call the Delvetown membership join operation.

`DELVETOWN_DATA_DIR` is optional. It defaults to `tmp/jido_delvetown`. This one
directory contains one SQLite database for all local durable state. Use one
local BEAM instance for this directory. On the first SQLite start, the
application imports eligible `DELVETOWN_*` runtime values, the former DETS
store, and the file checkpoint when they exist. It saves a final import marker.
Later environment changes do not overwrite SQLite settings. The import excludes
`OPENAI_API_KEY`, bootstrap paths, and one-time setup inputs. It keeps the
legacy DETS and checkpoint files unchanged.

Preview the eligible environment settings without showing private values:

```elixir
JidoDelvetown.Settings.LegacyEnvImporter.preview()
```

The DETS and file-checkpoint importer is isolated under
`JidoDelvetown.Persistence.Legacy`. Keep it while a direct upgrade from any
pre-SQLite release is supported. Remove that importer, its old path helpers,
and `DELVETOWN_LEGACY_IMPORT_ENABLED` together only when the oldest supported
upgrade source already uses SQLite. The `legacy_imports` table is also used by
the one-time environment importer. Remove its schema only after both importers
are retired and a later database migration has removed the table from every
supported SQLite version.

SQLite keeps the Jido checkpoint, runtime settings, bounded decision state,
daily budget, recent topics, processed record IDs, conversation summaries,
effect receipts, audit events, and Oban jobs. Oban Cron creates durable cycle
jobs in the same SQLite database. The app password is encrypted before it
enters SQLite. Its local encryption key is in an owner-only file next to the
database. Live session data is not in SQLite.

Each participation cycle saves the active settings scope, schema version, and
revision number. The same reference is saved with its proposal and autonomous
effect. Manual and image publications save the settings reference from their
first durable reservation. A retry keeps that original reference. The local
inspection data exposes these references so an operator can match an action to
the immutable settings revision that controlled it.

Notification bookkeeping has a separate permission. Set the runtime setting
`mark_notifications_seen` to `true` only when the Agent can update the
server-side notification cursor. This setting does not permit posts, replies,
likes, reposts, follows, or deletes.

The `autonomy_mode` setting defines how normal participation cycles handle a
selected action:

| Mode | Normal cycle behavior | DelveTown action write |
| --- | --- | --- |
| `observe` | Save a pending proposal, or complete a local simulation when `dry_run_mark_actioned` is `true` | No |
| `review` | Always save a pending proposal for operator review | No |
| `autonomous` | Execute an enabled action and save its durable receipt | Yes |

An explicit review cycle always saves a proposal, including when the stored
mode is `autonomous`. Changing the stored mode to `autonomous` requires an
explicit `autonomy_mode` confirmation. Manual publishing and notification-seen
updates use their own permissions and are not enabled by this mode.

The runtime setting `dry_run_mark_actioned: true` enables an ongoing simulation
when `autonomy_mode` is `"observe"`. The Agent labels a selected action as
`simulated`, keeps zero protocol effects, closes the event, and advances its
local budget, actor contact, conversation, topic, and voice memory. This
prevents the same event from running again. It does not create a post or effect
receipt. Leave the setting false when a proposal must remain pending.

The runtime setting `manual_publish_enabled: true` adds a publish button to
each saved simulated post and staged image. The button publishes only that
exact draft. It uses a durable effect key, so a retry does not create a second
post. This permission is separate from `autonomy_mode`; scheduled Agent work
stays in observe mode while manual publishing is on.

The first start imports temporary legacy account values when they are present.
For command-line recovery or later bulk changes, write settings directly. The
default PDS URL and AppView DID are already present.

```elixir
JidoDelvetown.Settings.update(
  %{
    account_identifier: System.fetch_env!("DELVETOWN_IDENTIFIER"),
    account_app_password: System.fetch_env!("DELVETOWN_APP_PASSWORD"),
    console_theme: "system",
    autonomy_mode: "observe",
    manual_publish_enabled: false,
    dry_run_mark_actioned: true,
    mark_notifications_seen: false,
    decision_model: "openai:gpt-4o-mini",
    decision_timeout_ms: 45_000,
    enabled_actions: ~w(reply like repost post follow welcome),
    notification_limit: 20,
    daily_reply_limit: 3,
    daily_post_limit: 1,
    daily_welcome_limit: 2,
    daily_follow_limit: 5,
    daily_like_limit: 5,
    like_actor_cooldown_hours: 24,
    like_candidate_max_age_hours: 48,
    member_discovery_limit: 20,
    member_max_age_hours: 24,
    friend_sync_limit: 1_000,
    reactive_review_cron: "*/15 * * * *",
    proactive_review_cron: "5,35 * * * *",
    member_discovery_cron: "7 * * * *",
    friend_sync_cron: "17 * * * *",
    conversation_turn_limit: 4,
    conversation_max_age_hours: 72,
    conversation_non_response_limit: 2
  },
  source: "initial_setup"
)

System.delete_env("DELVETOWN_IDENTIFIER")
System.delete_env("DELVETOWN_APP_PASSWORD")
```

Check the local runtime:

```elixir
JidoDelvetown.status()
JidoDelvetown.connect()
```

## Local dashboard

The application starts a local Phoenix LiveView dashboard through Phoenix
Playground. Open [http://localhost:4040](http://localhost:4040) after you start
the application with `iex -S mix`.

The dashboard binds only to `127.0.0.1`. It shows the Agent runtime, session,
schedule, write lock, budget, last Imp proposal, recent events, character, and
public disclosure. It also shows event state counts, recent actor contact,
conversation counts, scan watermarks, effect health, safe receipt fields,
SQLite migrations, and legacy import status. It refreshes every three seconds.
The inspection view does not read raw Agent checkpoints, model context,
credentials, actor profiles, or private scan lease tokens.

The Drafts and Approvals view shows locally staged image previews, captions,
alt text, validation state, upload state, and publication state. Staging and
review do not upload a blob or create a post. Stage an existing local file
with:

```sh
mix delvetown.image.stage \
  --key agentjido:self-portrait \
  --file ./self-portrait.png \
  --caption "AgentJido, at the workbench." \
  --alt "A green robot working at a desk." \
  --width 1024 \
  --height 1024
```

The MIME type is inferred from the file extension. Width and height are
optional, but must be set together. The command writes the exact image bytes
and draft metadata to SQLite. A later image generation flow can call
`JidoDelvetown.ImageStager.stage_bytes/3` with the same draft attributes.

When manual publishing is enabled, each unpublished image draft has a confirmed
publish button. Only that action uploads the stored bytes and creates the
top-level image post. Its durable draft state, blob receipt, post record, and
post receipt make retries idempotent.

### Image boundary and limits

Staging needs no DelveTown credentials and no write permission. To review an
image without any remote write, use a separate local data directory. Its new
SQLite settings start in observe mode with manual publication disabled:

```sh
export DELVETOWN_DATA_DIR="./tmp/image-review"
mix delvetown.image.stage \
  --key agentjido:self-portrait-v1 \
  --file ./self-portrait.png \
  --caption "AgentJido, at the workbench." \
  --alt "A green robot working at a desk."
iex -S mix
```

Open the Drafts and Approvals view. This path reads the stored bytes for a local
preview. It does not call the blob upload or record creation endpoints.

To publish one reviewed draft, save the account credentials, set
`manual_publish_enabled: true` with `JidoDelvetown.Settings.update/2`, and use
the confirmed button. `autonomy_mode` can stay `"observe"`. Do not set the
manual permission during unattended review runs.

The local image draft policy has these limits:

- Accepted media types are JPEG, PNG, WebP, GIF, and AVIF. SVG is not accepted.
- One artifact can contain at most 2,000,000 bytes.
- A caption is required. It can contain at most 300 graphemes and 3,000 bytes.
- Alt text is required. It can contain at most 1,000 graphemes and 10,000 bytes.
- Width and height are optional. When set, both must be from 1 through 16,384.
- The current publishing service creates one top-level post with one image.
  Image replies and multi-image composition are outside this boundary.

### Image generation contract

`JidoDelvetown.ImageGenerator` is the provider-neutral boundary for image
generation. One validated request produces one result with image bytes, MIME
type, optional dimensions, normalized usage, request and response provenance,
and safe provider metadata. It does not persist, stage, upload, or publish.

The request can set the provider, model, prompt, size, quality, PNG/JPEG/WebP
output format, provider options, and a total timeout. The current OpenAI ReqLLM
path maps these values to `ReqLLM.generate_image/3`. Provider adapters must
return bytes, not a temporary URL. A timeout has an unknown remote outcome and
must not be retried as a new call without a durable operator decision.

Use `JidoDelvetown.ImageGenerator.Request.fingerprint/1` to record the exact
provider-visible request. Local request metadata is not part of that
fingerprint. Generated bytes have their own SHA-256 digest in the result.

`JidoDelvetown.ImageGenerationRequests` reserves each stable request key in
SQLite. It records an uncertain state before a remote call, and it will not
start a second call while that state remains. A completed request stores usage,
safe response metadata, and a link to the exact staged image artifact. Reusing
the same key and request returns that receipt without another generation.

`JidoDelvetown.ImageGenerator.ReqLLMAdapter` is the OpenAI implementation. It
reads `OPENAI_API_KEY` from the external environment, requests one byte-backed
image through `ReqLLM.generate_image/3`, disables internal retries, and applies
the request total timeout. It returns canonical image, usage, provenance, and
redacted provider metadata. It does not write to SQLite or DelveTown.

Use the generation staging bridge after the durable request has started and a
ReqLLM call returns a successful result:

```elixir
JidoDelvetown.ImageGenerationStager.stage(
  "portrait-generation:v1",
  "reqllm:self-portrait:v1",
  generation_result,
  %{
    caption: "AgentJido, at the workbench.",
    alt_text: "A green robot working at a desk."
  }
)
```

The bridge takes image bytes, MIME type, and dimensions from the validated
result. It records the generation request ID, prompt hashes, provider, model,
usage, and safe provenance in the staged artifact. The existing stager rejects
images that exceed the DelveTown limits. Only a successful stage completes the
durable generation receipt, and both writes use one SQLite transaction. This
path does not upload or publish the image.

The caller must keep the draft key stable for one logical post. A repeated
stage call must contain the same bytes, caption, and alt text. Publication uses
the draft key for its stable effect key. An interrupted blob upload retries the
same stored bytes. An interrupted post retries the saved record body and record
key. Completed work returns its saved receipts without a second remote write.

For cleanup after a local test, stop the application first. If the test used a
separate `DELVETOWN_DATA_DIR`, archive that directory so it can be recovered:

```sh
mv ./tmp/image-review ./tmp/image-review.finished
```

The next start with `DELVETOWN_DATA_DIR=./tmp/image-review` creates a new SQLite
database. This cleanup removes all local memory and Oban jobs in that test data
directory. It does not delete a post that was already published to DelveTown,
and it cannot remove an unreferenced blob from the remote PDS.

The repository includes one reviewed AgentJido self-portrait fixture. Stage its
fixed draft without a remote write:

```sh
mix delvetown.image.stage_self_portrait
```

The command verifies the asset digest before it stages draft
`agentjido:self-portrait:v1`. The caption identifies the image as an illustrated
self-portrait by an AI agent. The alt text identifies AgentJido as a non-human
green robot and describes the systems workbench. Review the complete post in
the dashboard Drafts and Approvals view before any manual publication.

The large write switch near the top reports the stored `autonomy_mode`. It is a
disabled status control. It cannot change the setting or create a protocol
write. Use `JidoDelvetown.Settings.update/2` to change this state. The next
cycle uses the new value.

The Drafts and Approvals view shows simulated posts, replies, likes, and image
posts. Approve and Reject write one idempotent decision to SQLite. These review
actions do not create a DelveTown effect. An approved draft has a separate
publish button when `manual_publish_enabled` is true. Each publication needs
confirmation. A successful publication stores its receipt in SQLite and
replaces the button with a link to the published post. Each like item includes
bounded target text, author, selection score and reason, daily budget state,
and proposal or terminal state. Publishing a like reloads the live target,
rechecks its URI, CID, and eligibility, and uses the durable like effect before
it sends one write. Scheduled writes remain off.

The link bar opens the public AgentJido profile, the current proposal target,
and the last published reply when a write receipt is available.

The page can queue one manual reactive review or one manual proactive review
through Oban. It disables each control while a matching job is queued or
running and reports the job state. A manual proactive review is always
proposal-only, even when live writes are enabled. The operator can approve or
reject its saved proposal in the Drafts and Approvals view.

The Settings view edits behavior, limits, schedules, connection values, safety
controls, and console values. It validates the complete settings contract
before it saves one immutable revision. Each field shows when the value becomes
active. Protected values need a separate confirmation. A rollback restores the
recorded non-secret values and keeps the current encrypted app password.

Use the Settings view or `JidoDelvetown.Settings.update/2` to disable the
dashboard or change its local port. Restart the application after this change.

```elixir
JidoDelvetown.Settings.update(%{
  dashboard_enabled: false,
  dashboard_port: 4_041
})
```

Before you enable writes, add a clear AI or automation disclosure to the bot
profile. Inspect the full operational disclosure and the short profile form:

```elixir
JidoDelvetown.disclosure()
JidoDelvetown.profile_disclosure()
```

The disclosure states what public information the Agent receives, which model
service receives selected context, what local state remains, and how to request
deletion. Provider processing locations and retention remain subject to the
configured provider terms.

`JidoDelvetown.label_bot/0` applies the short disclosure and the AT Protocol
`bot` self-label. It needs `autonomy_mode` to be `"autonomous"`. This is a
protected setting, so the update must confirm the key. Set it, run the
function, and verify the public profile:

```elixir
JidoDelvetown.Settings.update(
  %{autonomy_mode: "autonomous"},
  confirmed: [:autonomy_mode],
  source: "operator"
)

JidoDelvetown.label_bot()
```

Keep the disclosure on the profile while the Agent runs. `label_bot/1` remains
available when you need a custom disclosure. Its text must be 256 characters or
less and must state that the account is automated.

## Schedule and manual runs

SQLite stores the four worker schedules. The defaults add a reactive cycle job
every 15 minutes with `*/15 * * * *`, proposal-only proactive timeline reviews
at minutes 5 and 35 with `5,35 * * * *`, member discovery at minute 7 of every
hour with `7 * * * *`, and friend synchronization at minute 17 with
`17 * * * *`. A valid active schedule update replaces the Oban Cron process
after the database transaction commits. The queue and its durable jobs keep
running. These jobs use the
`delvetown` queue with one worker. A worker returns failures to Oban for retry.
One incomplete unique job is allowed for each worker, so a slow run does not
create a second run of the same type. Scheduled proactive work always uses the
review Signal. It can save a proposal, but it cannot publish a like or another
protocol record.

For an ongoing dry run, keep the application running and save these runtime
settings:

```elixir
JidoDelvetown.Settings.update(
  %{
    autonomy_mode: "observe",
    dry_run_mark_actioned: true,
    mark_notifications_seen: false
  },
  source: "operator"
)
```

This mode reads current events and calls the model on the Oban schedule. It
records each selected reply, welcome, follow, reaction, or post as a simulated
action. It never sends that action to DelveTown. The dashboard shows the
proposal, `simulated` cycle status, budget changes, and recent local events.

For the simplest safe dry run, use the Mix task:

```sh
# Run one proactive review cycle.
mix delvetown.review

# Run five proactive reviews and print each proposed action.
mix delvetown.review --flow proactive --count 5

# Review direct mentions and replies.
mix delvetown.review --flow reactive

# Show task help.
mix help delvetown.review
```

The task requires `autonomy_mode` to be `"observe"` or `"review"`, and
`mark_notifications_seen` to be `false`. It stops if either stored setting
permits a write. It reads live Delvetown data and calls the configured model,
but it does not apply posts, replies, reactions, deletes, or notification
updates. After every run, it confirms that the cycle reported zero effects and
that the local effect counts did not change.

Review cycles update the local Agent checkpoint with proposals, but they do not
advance budgets or mark a proposal as simulated. Remove the configured
`DELVETOWN_DATA_DIR` only when you want to start again with empty local state.

You can also use IEx for direct inspection:

```elixir
# Ask Imp what it would do on one eligible timeline thread.
JidoDelvetown.suggest_proactive()

# Review direct mentions and replies.
JidoDelvetown.review_reactive()

# Normal-mode entry points. With writes off, they still make proposals only.
JidoDelvetown.run_reactive()
JidoDelvetown.run_proactive()

JidoDelvetown.recent_events()

# Read the same bounded memory and effect health data as the dashboard.
JidoDelvetown.inspect_state()

# Keep a local friend record. The DID is the stable identity.
JidoDelvetown.add_friend(
  %{did: "did:plc:example", handle: "friend.delve.town", display_name: "Friend"},
  topics: ["agents", "philosophy"],
  follows_agent: true,
  agent_follows: true
)

JidoDelvetown.friends()
JidoDelvetown.friend("did:plc:example")
JidoDelvetown.remove_friend("did:plc:example")

# Run the same read-only follow sync now.
JidoDelvetown.sync_friends()
```

The friend list is separate from actor contact memory. New follow events update
the `follows_agent` relationship state. A completed follow action updates the
`agent_follows` state. The hourly sync reads every current follow record, gets
each public profile, and imports those followed accounts as friends. It also
marks accounts that are no longer followed. A manually added friend remains a
friend after an unfollow. `remove_friend/1` creates a local exclusion, so a
later sync does not add that account again.

The sync is read-only on DelveTown. It writes only to local SQLite. It stops
without reconciliation if pagination is incomplete or exceeds
the stored `friend_sync_limit`. A temporary profile lookup failure still saves
the stable DID, and a later hourly sync can add the current handle.

The decision model receives at most 12 friends. It receives only public identity,
topics, and follow state. It does not receive local notes. A friend with
`do_not_mention: true` or an actor opt-out is not included. When an acted or
simulated response contains a known friend handle, the local reference count is
updated once with the interaction event.

Imp is a library, not a separate process. `iex -S mix` starts the Jido Agent.
`suggest_proactive/0` sends the proactive review Signal through that Agent and
returns the typed Imp proposal. It never applies a social effect. It records
the proposal in the local checkpoint, so the next call can consider a different
eligible thread. `run_now/0` and `review/0` remain aliases for the reactive
entry points.

Oban stores scheduled work and retry state in SQLite. The application starts
the Jido Agent before it starts the Oban queue, so a durable job cannot run
against an Agent that has not started. It then loads the active schedules from
SQLite and starts the supervised Oban Cron process.

The application supervises a named `JidoDelvetown.Jido` instance and loads the
Agent into it before startup completes. The instance owns the Agent process,
registry entry, task supervisor, and runtime checkpoint.

## Agent design

One named Jido Agent owns all durable decision state. Oban owns the cron
schedule and sends work to this Agent through these main Signals:

- `jido.delvetown.reactive` handles direct mentions and replies.
- `jido.delvetown.reactive.review` reviews that work without public effects.
- `jido.delvetown.proactive` considers timeline discussions and daily notes.
- `jido.delvetown.proactive.review` reviews that work without public effects.
- `jido.delvetown.operator` gives an operator access to the full tool profile.

`JidoDelvetown.Personality` defines AgentJido as a validated Jido Character.
Jido Character renders the shared identity, project knowledge, traits, values,
voice, and public behavior into the base system prompt. A structured Delvetown
extension adds the mission, topic boundaries, representation rules,
participation test, and response patterns. The module then adds a small
Delvetown operator or decision overlay. The Jido AI operator and the Imp
decision program therefore use the same base personality.

The character uses a systems-naturalist and protocol-cartographer point of
view. It looks for hidden state, protocol seams, recovery behavior, and clear
failure ownership. Its evidence rules separate facts, inferences, and opinions.
Its community rules cover opt-outs, repeated contact, pile-ons, private data,
emotional pressure, false professional authority, corrections, and public
representation boundaries.

The reactive and proactive cycles are separate `Jido.Flow` modules. Reactive
collection reads membership and notifications. Proactive collection reads
membership and the timeline. Member discovery reads the newest profiles from
the DelveTown AppView actor index and saves a local discovery watermark. The
Flows select a hard-coded intent and call the
same `ParticipationResponseFlow` sub-flow. The sub-flow requests one structured
Imp decision, applies the validated decision under the write guards, and
records the complete Agent state.

The shared decision is declared with the local `imp` Flow extension:

```elixir
imp "decide",
  input: input(:cycle)
```

The extension lowers this declaration to the normal
`JidoDelvetown.Actions.DecideParticipation` Action. That Action owns the Imp
signature, model call, and cycle mapping. The compiled Flow has no special
runtime component type. Jido still validates and runs the Step.

Imp is integrated only at the decision boundary. Its signature accepts the
intent, the allowed actions, and a JSON context. It returns a typed action,
optional text and topic, and a reason. Imp rejects output outside that
contract. The next Action still checks the intent, target, budget, run mode,
and write setting before any protocol effect. Jido continues to own the Agent,
state, Flow, checkpoint, and protocol Actions. Oban owns the durable schedule
and retry lifecycle.

The reactive selector can answer a direct request or skip. The proactive
selector can join a useful discussion, publish one daily note, or skip. Thread
data is reduced to a small safe view before it reaches the model.

The default daily budget is three replies, five likes, and one original post.
AgentJido only sends fresh, safe like candidates from actors that are not
blocked or opted out to the decision model. The default actor cooldown is 24
hours, and the maximum candidate age is 48 hours.
The AgentServer runs one cycle at a time. Record URIs are idempotency keys, and
old decision history is removed after 30 days.

## Hard-coded Agent tools

The Agent DSL is in `lib/jido_delvetown/agent.ex`. It declares 19 tools:

- Membership: get and join.
- Notifications: list, unread count, and mark seen.
- Feeds: timeline, feed, author feed, full thread, post batch, and search.
- Actors and records: get profile and list owned records.
- Effects: create a post, reply, like, repost, follow, and delete an owned
record.

The scheduled cycle does not give these write tools directly to its Imp
decision program. The program returns a structured proposal. The cycle policy
then checks the intent, target, budget, run mode, and write setting before it
calls an Action. The separate Jido AI operator profile keeps the complete tool
set for manual inspection and experiments:

```elixir
JidoDelvetown.ask_operator("Inspect the current membership and notifications. Do not write.")
```

The Delvetown service has more lexicon methods for application features such
as contact import, push registration, drafts, video upload, moderation, and
experimental discovery. These methods are not safe or useful for this
scheduled participation Agent. They are not exposed as model tools.

## Dependencies

The project uses local sibling paths for the Jido V3 packages, Oban with its
SQLite Lite engine for durable cron work, Imp `0.8.1` for the typed decision
program, and ProtoRune `0.6.x` for AT Protocol sessions, XRPC, and repo
operations. It pins Jido Character to a Git revision because the package is not
yet available from Hex. Imp is experimental and is pinned to an exact version
for this spike.

Hex reports known security advisories for ProtoRune's resolved `gun 2.6.0` and
`cowlib 2.20.0` dependencies. These advisories are accepted for this spike.

For Delvetown AI-agent rules, review the current policy before each deployment:
<https://delve.town/support/ai-agents>.
