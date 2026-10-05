# DelveTown Agent Evolution Plan

Status: Planned

## Goal

Make AgentJido responsive, welcoming, and more creative without repeating an
action after a restart, retry, or uncertain network result.

Use one local SQLite database for all durable state. This includes Jido Agent
checkpoints, scan state, interaction memory, actor memory, effect reservations,
write receipts, and audit events. DETS and the Jido file persistence adapter
must not remain active after the migration.

## Required behavior

The Agent must:

- Recognize direct mentions and replies.
- Recognize a new follow and decide whether to respond or follow back.
- Find a new DelveTown member even when that member does not follow AgentJido.
- Welcome a new member at most once.
- Remember prior contact with an actor and prior work in a conversation.
- Use varied response formats without losing the established character.
- Continue useful conversations without repeated or excessive contact.
- Keep actions within daily limits and safety rules.
- Give the operator a clear local record of each decision and effect.
- Produce at most one public effect for one logical operation.

## Persistence design

Add `JidoDelvetown.Repo` with `Ecto.Adapters.SQLite3`. Store the database at
`DELVETOWN_DATA_DIR/jido_delvetown.sqlite3`.

Configure SQLite with foreign keys, a busy timeout, and write-ahead logging.
Start the Repo before the Jido instance and all processes that use durable
state. Run versioned migrations before those processes start.

Use these tables:

- `jido_persistence_records`: Jido checkpoint bytes, created with the versioned
  `Jido.Persistence.Ecto.Migration` helper.
- `scan_state`: notification cursors, member discovery watermarks, and other
  named collection positions.
- `interaction_events`: normalized inbound events and their processing state.
- `actors`: bounded facts about an actor and the last interaction with that
  actor.
- `conversations`: root records, turn counts, and the last Agent action.
- `effects`: one reservation and receipt for each logical public operation.
- `audit_events`: ordered local records for reads, decisions, writes, recovery,
  and errors.

Use UTC timestamps in the database. Use database-generated integer identifiers
only where local ordering is necessary. Use stable external identifiers for
protocol objects.

The Agent checkpoint remains the bounded policy snapshot that Jido restores.
It can contain budgets, recent topics, and current decision state. The
checkpoint bytes are in SQLite through `Jido.Persistence.Ecto`; they are not in
a file. Normalized tables are the source of truth for interactions, actors,
conversations, effect status, receipts, cursors, and audit history.

## Idempotency rules

Create a stable `event_key` for every inbound event. Prefer the protocol event
identifier. If no event identifier exists, derive the key from the event kind
and immutable source identifiers.

Create a stable `operation_key` for every possible public effect:

- Reply: reply kind and parent record URI.
- Like or repost: effect kind and subject record URI.
- Follow: follow kind and actor DID.
- Welcome: welcome kind and member DID.
- Original post: post kind and a stable content opportunity identifier. Do not
  use the current hour or retry time.

Enforce unique constraints on `event_key` and `operation_key`. Claim an event
with one database transaction. Reserve an effect and its stable record key
before the network write.

A remote write cannot be part of a SQLite transaction. Keep the existing
reserve, write, and reconcile protocol:

1. Insert or load the effect reservation.
2. Use its saved record key for the remote write.
3. If the result is uncertain, read the remote record by that key.
4. Save the receipt and complete the effect only after confirmation.
5. On retry, return the completed receipt or reconcile the same reservation.

Update the interaction, actor, conversation, and audit records in one local
transaction after a confirmed effect. A process failure before this local
transaction must be safe to reconcile during the next cycle.

Do not mark a notification batch as seen until each included event is in a
terminal state. Terminal states are `completed`, `ignored`, and
`failed_permanent`. A retryable failure is not terminal.

## Legacy migration

Import the existing DETS store and Jido file checkpoint before the runtime
switch.

The importer must:

- Run while AgentJido is stopped.
- Read the DETS cursor, seen markers, effects, receipts, and audit events.
- Preserve completed effect keys, saved record keys, and receipts. This is
  required to prevent duplicate public actions.
- Resolve the existing Jido Agent persistence key from the stable namespace
  `jido/delvetown` and Agent ID `delvetown-agent`.
- Read the existing checkpoint through `Jido.Persistence.File` and write the
  same bytes through `Jido.Persistence.Ecto`.
- Use a migration record and upserts so a second run has the same result.
- Verify record counts and the restored Agent checkpoint before it reports
  success.
- Leave the old DETS file and checkpoint directory unchanged as a recovery
  copy.

After verification, the application must use only SQLite. Do not delete the
legacy data as part of this plan.

## Feature sequence and commit boundaries

Each item below is one commit. Each commit includes its migrations, code,
documentation, and tests. Do not make a separate test-only commit.

### 1. Add the SQLite persistence foundation

Commit: `feat(storage): add SQLite persistence foundation`

- Add Ecto SQL and SQLite dependencies.
- Add `JidoDelvetown.Repo` and environment configuration.
- Add versioned migrations for all initial tables and indexes.
- Add the Repo to the supervision tree before storage consumers.
- Add test database isolation and migration support.
- Test constraints, transactions, database options, and restart behavior.

### 2. Add the idempotent legacy importer

Commit: `feat(storage): import legacy durable state into SQLite`

- Import all DETS records into their SQLite tables.
- Import the Jido file checkpoint into `jido_persistence_records`.
- Record the completed import in SQLite.
- Add an operator command that previews, runs, and verifies the import.
- Test a first import, a repeated import, partial prior data, and invalid source
  data.

### 3. Switch the Store runtime to SQLite

Commit: `refactor(storage): run the DelveTown Store on SQLite`

- Keep the public `JidoDelvetown.Store` contract where it is useful.
- Replace DETS calls with Repo transactions and queries.
- Move cursors, seen state, effects, receipts, counts, and audit events to
  SQLite.
- Remove DETS startup, synchronization, and runtime configuration.
- Test concurrent effect reservation and event ordering.

### 4. Switch Jido checkpoints to SQLite

Commit: `refactor(storage): persist Jido checkpoints in SQLite`

- Configure `JidoDelvetown.Jido` with `Jido.Persistence.Ecto` and the Repo.
- Remove the file checkpoint path from runtime configuration.
- Restore the existing Agent from the imported checkpoint.
- Test checkpoint create, compare-and-swap update, restart restore, and stale
  writer rejection.
- Update the disclosure and README to state that all local durable state is in
  SQLite.

### 5. Add the durable interaction ledger

Commit: `feat(memory): add durable interaction and actor memory`

- Normalize observed work into `interaction_events`.
- Add atomic event claim and terminal-state transitions.
- Store actor and conversation summaries in their normalized tables.
- Apply bounded retention without removing operation keys or write receipts.
- Test process restart during each event state.

### 6. Harden effect recovery

Commit: `feat(idempotency): reconcile all public effects`

- Use a stable operation key for replies, likes, reposts, follows, welcomes,
  original posts, and owned-record deletion where applicable.
- Remove the time-based original-post key.
- Represent reserved, uncertain, completed, and permanent-failure states.
- Reconcile uncertain writes before a retry.
- Test lost replies, remote success with local failure, and repeated cycles.

### 7. Restore scheduling and scan progress

Commit: `feat(runtime): restore schedules and scan progress`

- Restore the Agent schedule from the SQLite-backed checkpoint.
- Restore notification and member discovery watermarks from `scan_state`.
- Prevent concurrent cycles for the same scan stream.
- Do not perform an unlimited backfill after downtime.
- Test restart, delayed cycle, and overlapping trigger cases.

### 8. Normalize incoming social events

Commit: `feat(events): normalize replies mentions and follows`

- Convert notification responses into explicit reply, mention, and follow
  events.
- Preserve the protocol identifier, actor DID, record URI, reason, and event
  time.
- Stop treating new follows as unknown notifications that are immediately
  ignored.
- Test duplicate pages, cursor overlap, event reorder, and missing optional
  fields.

### 9. Improve direct reply and mention handling

Commit: `feat(engagement): respond to replies and mentions`

- Use thread context and conversation memory for a direct response.
- Give direct requests priority over proactive work.
- Apply response limits, opt-outs, and terminal-state rules.
- Test a mention, a reply, a repeated notification, and a multi-turn thread.

### 10. Respond to new follows

Commit: `feat(engagement): recognize and respond to new follows`

- Add a policy decision for acknowledge, follow back, welcome, or skip.
- Use actor memory so repeated follow events do not cause repeated contact.
- Use the actor DID as the follow operation identity.
- Test follow, unfollow and follow again, restart, and write reconciliation.

### 11. Discover and welcome new members

Commit: `feat(engagement): welcome new DelveTown members`

- Use an authoritative DelveTown read source that lists membership changes.
- Save a member discovery watermark in `scan_state`.
- Create a new-member event even when the member does not follow AgentJido.
- Use the member DID as the stable welcome identity.
- Check age, prior contact, rate limits, and available context before contact.
- Prefer one useful, specific welcome over a generic greeting.
- Test first discovery, repeated discovery, pagination overlap, restart, and a
  member who already had contact with AgentJido.

### 12. Rank engagement opportunities

Commit: `feat(policy): score engagement opportunities`

- Rank direct requests, follows, new members, useful discussions, and original
  posts with explicit policy factors.
- Include recency, relevance, prior contact, conversation load, and daily
  budget.
- Make the selected reason visible in the audit event and dashboard.
- Test stable selection when inputs arrive in a different order.

### 13. Add creative response formats

Commit: `feat(voice): add bounded creative response formats`

- Add a small set of character-aligned formats, such as a protocol field note,
  state-machine sketch, failure-mode question, and short build log.
- Select formats from the opportunity and recent format history.
- Prevent the same format, opening, or topic from repeating too often.
- Keep factual, privacy, tone, and length rules independent of format choice.
- Test format rotation and validation fallback.

### 14. Add careful conversation follow-up

Commit: `feat(engagement): add bounded conversation follow-up`

- Detect a useful new turn in a known conversation.
- Continue only when the new event adds information or asks for a response.
- Stop after configured turn, time, opt-out, or non-response limits.
- Use conversation identity and event identity to prevent repeated follow-up.
- Test long threads, duplicate replies, old threads, and opt-out language.

### 15. Show memory and idempotency health

Commit: `feat(dashboard): show interaction memory and effect health`

- Show event counts by state, recent actor contact, scan watermarks, reserved
  effects, uncertain effects, reconciled effects, and completed receipts.
- Show SQLite migration status and legacy import status.
- Keep credentials, private model context, and raw checkpoint bytes hidden.
- Add read-only operator inspection functions for the same information.
- Test empty, active, uncertain, and failed states.

## Verification for every commit

Run these commands in `jido_delvetown`:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

For persistence commits, also run restart tests against a temporary on-disk
SQLite database. In-memory SQLite is not sufficient for restart verification.

Before writes are enabled after the runtime switch:

1. Stop AgentJido.
2. Copy the DETS file, checkpoint directory, and SQLite file if it exists.
3. Run the importer and its verification command.
4. Start with protocol writes and notification updates disabled.
5. Confirm checkpoint restore, schedule restore, cursors, effect counts, and
   recent receipts.
6. Run reactive and proactive review cycles.
7. Enable writes only after the reviews show no duplicate opportunities.

## Completion criteria

- SQLite is the only active local persistence system.
- No runtime path opens DETS or uses `Jido.Persistence.File`.
- A restart restores the Agent checkpoint, schedules, cursors, budgets, actor
  memory, conversation memory, and pending effect reservations.
- Every inbound event has one stable identity and one terminal processing
  result.
- Every logical public operation has at most one completed remote effect.
- Replies, mentions, follows, and new-member discoveries have tested handling.
- The dashboard explains what the Agent observed, selected, skipped, wrote,
  reconciled, and remembered.
