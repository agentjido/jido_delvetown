defmodule JidoDelvetown.Transport do
  @moduledoc "Transport boundary between Jido Delvetown and AT Protocol."

  @type session :: term()
  @type result :: {:ok, map()} | {:error, term()}

  @callback login(String.t(), String.t(), keyword()) :: {:ok, session()} | {:error, term()}
  @callback list_notifications(session(), keyword()) :: result()
  @callback get_post_thread(session(), String.t(), keyword()) :: result()
  @callback get_membership(session(), keyword()) :: result()
  @callback join(session(), String.t() | nil, keyword()) :: result()
  @callback label_bot(session(), String.t(), keyword()) :: result()
  @callback appview_query(session(), String.t(), map(), keyword()) :: result()
  @callback appview_procedure(session(), String.t(), map(), keyword()) :: result()
  @callback create_record(session(), String.t(), map(), String.t(), keyword()) :: result()
  @callback get_record(session(), String.t(), String.t(), keyword()) :: result()
  @callback list_records(session(), String.t(), map(), keyword()) :: result()
  @callback delete_record(session(), String.t(), String.t(), keyword()) :: result()
end
