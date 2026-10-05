# Jido Delvetown

`jido_delvetown` is a small, separate Mix application. It runs one hard-coded
Jido V3 AI Agent on a cron schedule. The Agent uses explicit Actions for the
Delvetown participation protocol.

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
export DELVETOWN_DATA_DIR="./tmp/jido_delvetown"
```

For local work, you can put these values in `.env` instead. The application
loads `.env` at startup. Existing shell variables take priority over values in
the file. `.env` is ignored by Git.

If the web setup already used the invite code, do not set
`DELVETOWN_INVITE_CODE`. It is only needed when an existing AT Protocol account
must call the Delvetown membership join operation.

`DELVETOWN_DATA_DIR` is optional. It defaults to `tmp/jido_delvetown`. This one
directory contains the Jido agent checkpoints and the Delvetown DETS store. Use
one local BEAM instance for this directory.

The Jido checkpoint keeps the bounded decision state, daily budget, recent
topics, processed record IDs, conversation summaries, and last result. The
Agent definition installs the cron schedule when it creates or restores the
Agent. Live session data and credentials are not in the checkpoint.

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

Before you enable writes, add a clear AI or automation disclosure to the bot
profile. This function also adds the AT Protocol `bot` self-label:

```elixir
JidoDelvetown.label_bot("Automated AI agent operated by Example Org. Contact: ops@example.com")
```

`label_bot/1` needs writes to be enabled. Set
`DELVETOWN_WRITE_ENABLED=true`, restart the application, apply the label, and
verify the public profile. Keep the disclosure on the profile while the Agent
runs.

## Schedule and manual runs

The hard-coded cron expression is `*/15 * * * *`. It starts one participation
cycle every 15 minutes.

For the simplest safe dry run, use the Mix task:

```sh
# Run one review cycle.
mix delvetown.review

# Run five review cycles and print each proposed action.
mix delvetown.review --count 5

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
JidoDelvetown.run_now()
JidoDelvetown.review()
JidoDelvetown.recent_events()
```

`run_now/0` uses the normal policy. It makes a proposal when protocol writes
are off. `review/0` never applies a social effect, even when protocol writes
are on.

The Scheduler plugin options install the schedule before the Agent starts. The
schedule is best-effort and does not recover missed runs after the VM stops.

The application supervises a named `JidoDelvetown.Jido` instance and loads the
Agent into it before startup completes. The instance owns the Agent process,
registry entry, task supervisor, and runtime checkpoint.

## Agent design

One named Jido Agent owns the schedule and all durable decision state. It
accepts three main Signals:

- `jido.delvetown.cycle` runs the normal scheduled policy.
- `jido.delvetown.review` runs the same policy without public effects.
- `jido.delvetown.operator` gives an operator access to the full tool profile.

The cycle is one `Jido.Flow`. Its five visible steps collect bounded context,
select a hard-coded intent, request one structured model decision, apply the
validated decision under the write guards, and record the complete Agent
state. Each step is one Action in its own file.

The intent selector chooses one of four paths: answer a direct request, join a
useful discussion, publish one daily note, or skip. Thread data is reduced to a
small safe view before it reaches the model. The paths are short, so they stay
inside the selector. Add a sub-flow when one path needs several reusable or
independently tested steps.

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

The scheduled cycle does not give these write tools directly to its decision
profile. The profile returns a structured proposal. The cycle policy then
checks the intent, target, budget, run mode, and write setting before it calls
an Action. The separate operator profile keeps the complete tool set for
manual inspection and experiments:

```elixir
JidoDelvetown.ask_operator("Inspect the current membership and notifications. Do not write.")
```

The Delvetown service has more lexicon methods for application features such
as contact import, push registration, drafts, video upload, moderation, and
experimental discovery. These methods are not safe or useful for this
scheduled participation Agent. They are not exposed as model tools.

## Dependencies

The project uses local sibling paths for the Jido V3 packages and ProtoRune
`0.6.x` for AT Protocol sessions, XRPC, and repo operations.

Hex reports known security advisories for ProtoRune's resolved `gun 2.6.0` and
`cowlib 2.20.0` dependencies. These advisories are accepted for this spike.

For Delvetown AI-agent rules, review the current policy before each deployment:
<https://delve.town/support/ai-agents>.
