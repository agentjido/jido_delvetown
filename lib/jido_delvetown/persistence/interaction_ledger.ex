defmodule JidoDelvetown.InteractionLedger do
  @moduledoc "Compatibility facade for durable interaction memory."

  alias JidoDelvetown.{
    ActorMemory,
    ConversationMemory,
    CycleRecorder,
    InteractionEvents
  }

  def event_key(kind, values), do: InteractionEvents.event_key(kind, values)

  def observe_candidates(candidates, opts \\ []),
    do: InteractionEvents.observe_candidates(candidates, opts)

  def observe(attrs, opts \\ []), do: InteractionEvents.observe(attrs, opts)
  def claim(event_key, opts \\ []), do: InteractionEvents.claim(event_key, opts)

  def finish(event_key, outcome, details \\ %{}, opts \\ []),
    do: InteractionEvents.finish(event_key, outcome, details, opts)

  def recover_stale_claims(opts \\ []), do: InteractionEvents.recover_stale_claims(opts)

  def record_cycle(cycle, decision, completed_at),
    do: CycleRecorder.record(cycle, decision, completed_at)

  def actor(did, opts \\ []), do: ActorMemory.get(did, opts)
  def conversation(root_uri, opts \\ []), do: ConversationMemory.get(root_uri, opts)
  def event(event_key, opts \\ []), do: InteractionEvents.get(event_key, opts)

  def record_manual_publication(event_key, details, opts \\ []),
    do: InteractionEvents.record_manual_publication(event_key, details, opts)

  def processable_event?(event_key, opts \\ []),
    do: InteractionEvents.processable?(event_key, opts)

  def pending_events?(kinds, opts \\ []), do: InteractionEvents.pending?(kinds, opts)

  def outreach_count(kind, since, opts \\ []),
    do: InteractionEvents.outreach_count(kind, since, opts)

  def recent_outreach_for_actor?(kind, actor_did, since, opts \\ []),
    do: InteractionEvents.recent_outreach_for_actor?(kind, actor_did, since, opts)

  def context_for(candidate, opts \\ []) when is_map(candidate) do
    %{
      actor: ActorMemory.context(get_in(candidate, [:author, :did]), opts),
      conversation: ConversationMemory.context(get_in(candidate, [:root, :uri]), opts)
    }
  end

  def events_terminal?(candidates, opts \\ []),
    do: InteractionEvents.all_terminal?(candidates, opts)

  def prune(opts \\ []), do: InteractionEvents.prune(opts)
end
