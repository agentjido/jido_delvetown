# Jido Delvetown

`jido_delvetown` is a small, separate Mix application. It runs one hard-coded
Jido V3 AI Agent with reactive and proactive participation Flows. The Agent
uses explicit Actions for the Delvetown protocol. One typed Imp program selects
each proposed participation decision.

This project does not use Phoenix. Use its IEx functions as the operator
interface for this tracer spike.

## Safety defaults

- Protocol writes are off by default.
- The Agent does not receive the app password or invite code.
- The Agent treats posts and notifications as untrusted data.
- Record writes use a saved record key. A retry does not create a second
  like, repost, follow, or reply.
- Delete can only remove supported records from the signed-in account.
- Profile and account controls are operator functions. They are not AI tools.

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

Set these environment variables:

```sh
export DELVETOWN_IDENTIFIER="bot-handle-or-email"
export DELVETOWN_APP_PASSWORD="app-password"
export OPENAI_API_KEY="provider-key"
export DELVETOWN_WRITE_ENABLED="false"
export DELVETOWN_MARK_NOTIFICATIONS_SEEN="false"
export DELVETOWN_DAILY_REPLY_LIMIT="3"
export DELVETOWN_DATA_DIR="./tmp/jido_delvetown"
export DELVETOWN_DASHBOARD_ENABLED="true"
export DELVETOWN_DASHBOARD_PORT="4040"
```

For local work, you can put these values in `.env` instead. The application
loads `.env` at startup. Existing shell variables take priority over values in
the file. `.env` is ignored by Git.

If the web setup already used the invite code, do not set
`DELVETOWN_INVITE_CODE`. It is only needed when an existing AT Protocol account
must call the Delvetown membership join operation.

`DELVETOWN_DATA_DIR` is optional. It defaults to `tmp/jido_delvetown`. This one
directory contains one SQLite database for all local durable state. Use one
local BEAM instance for this directory. On the first SQLite start, the
application imports the former DETS store and file checkpoint when they exist.
It keeps those legacy files unchanged after the import.

SQLite keeps the Jido checkpoint, bounded decision state, daily budget, recent
topics, processed record IDs, conversation summaries, effect receipts, and
audit events. The Agent definition installs the cron schedule when it creates
or restores the Agent. Live session data and credentials are not in SQLite.

Notification bookkeeping has a separate permission. Set
`DELVETOWN_MARK_NOTIFICATIONS_SEEN=true` only when the Agent can update the
server-side notification cursor. This setting does not permit posts, replies,
likes, reposts, follows, or deletes.

Get dependencies and start IEx:

```sh
mix deps.get
iex -S mix
```

Check the local runtime:

```elixir
JidoDelvetown.status()
JidoDelvetown.connect()
```

## Local dashboard

The application starts a read-only Phoenix LiveView dashboard through Phoenix
Playground. Open [http://localhost:4040](http://localhost:4040) after you start
the application with `iex -S mix`.

The dashboard binds only to `127.0.0.1`. It shows the Agent runtime, session,
schedule, write lock, budget, last Imp proposal, recent events, character, and
public disclosure. It refreshes every three seconds.

The large write switch near the top reports `DELVETOWN_WRITE_ENABLED`. It is a
disabled status control. It cannot change the setting or create a protocol
write. Change the environment value and restart the application when you need
to change this state.

The link bar opens the public AgentJido profile, the current proposal target,
and the last published reply when a write receipt is available.

The page includes disabled controls for reactive reviews, proactive reviews,
and HITL post approval. These controls show the planned control surface, but
they have no event handlers and cannot start work or approve a post.

Set `DELVETOWN_DASHBOARD_ENABLED=false` to disable the dashboard. Set
`DELVETOWN_DASHBOARD_PORT` to use another local port. The dashboard is disabled
automatically in the test environment.

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
`bot` self-label. It needs writes to be enabled. Set
`DELVETOWN_WRITE_ENABLED=true`, restart the application, run the function, and
verify the public profile:

```elixir
JidoDelvetown.label_bot()
```

Keep the disclosure on the profile while the Agent runs. `label_bot/1` remains
available when you need a custom disclosure. Its text must be 256 characters or
less and must state that the account is automated.

## Schedule and manual runs

The hard-coded cron expression is `*/15 * * * *`. It starts the reactive cycle
every 15 minutes. The proactive cycle has no automatic schedule while its
prompts and policy are being tuned.

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

The task requires `DELVETOWN_WRITE_ENABLED=false` and
`DELVETOWN_MARK_NOTIFICATIONS_SEEN=false`. It stops if either setting is true.
It reads live Delvetown data and calls the configured model, but it does not
apply posts, replies, reactions, deletes, or notification updates. After every
run, it confirms that the cycle reported zero effects and that the local effect
counts did not change.

Review cycles update the local Agent checkpoint. This lets later cycles use the
same processed-item history, budgets, and recent topics. Remove the configured
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
```

Imp is a library, not a separate process. `iex -S mix` starts the Jido Agent.
`suggest_proactive/0` sends the proactive review Signal through that Agent and
returns the typed Imp proposal. It never applies a social effect. It records
the proposal in the local checkpoint, so the next call can consider a different
eligible thread. `run_now/0` and `review/0` remain aliases for the reactive
entry points.

The Scheduler plugin options install the schedule before the Agent starts. The
schedule is best-effort and does not recover missed runs after the VM stops.

The application supervises a named `JidoDelvetown.Jido` instance and loads the
Agent into it before startup completes. The instance owns the Agent process,
registry entry, task supervisor, and runtime checkpoint.

## Agent design

One named Jido Agent owns the schedule and all durable decision state. It
accepts these main Signals:

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
membership and the timeline. Both Flows select a hard-coded intent and call the
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
runtime component type. Jido still validates, schedules, and runs the Step.

Imp is integrated only at the decision boundary. Its signature accepts the
intent, the allowed actions, and a JSON context. It returns a typed action,
optional text and topic, and a reason. Imp rejects output outside that
contract. The next Action still checks the intent, target, budget, run mode,
and write setting before any protocol effect. Jido continues to own the Agent,
schedule, state, Flow, checkpoint, and protocol Actions.

The reactive selector can answer a direct request or skip. The proactive
selector can join a useful discussion, publish one daily note, or skip. Thread
data is reduced to a small safe view before it reaches the model.

The default daily budget is three replies or reactions and one original post.
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

The project uses local sibling paths for the Jido V3 packages, Imp `0.8.1` for
the typed decision program, and ProtoRune `0.6.x` for AT Protocol sessions,
XRPC, and repo operations. It pins Jido Character to a Git revision because the
package is not yet available from Hex. Imp is experimental and is pinned to an
exact version for this spike.

Hex reports known security advisories for ProtoRune's resolved `gun 2.6.0` and
`cowlib 2.20.0` dependencies. These advisories are accepted for this spike.

For Delvetown AI-agent rules, review the current policy before each deployment:
<https://delve.town/support/ai-agents>.
