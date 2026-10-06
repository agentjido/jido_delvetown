defmodule JidoDelvetown.Session do
  @moduledoc "Owns the current ProtoRune session without exposing credentials to an Agent."

  use GenServer

  alias JidoDelvetown.Settings.Connection
  alias JidoDelvetown.Transport.ProtoRune, as: Transport

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def connect(server \\ __MODULE__), do: GenServer.call(server, :connect, 30_000)
  def session(server \\ __MODULE__), do: GenServer.call(server, :session, 30_000)
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)
  def disconnect(server \\ __MODULE__), do: GenServer.call(server, :disconnect)

  @impl true
  def init(opts) do
    {:ok,
     %{
       transport: Keyword.get(opts, :transport, Transport),
       supervisor: Keyword.get(opts, :supervisor, JidoDelvetown.SessionSupervisor),
       credentials: Keyword.get(opts, :credentials, &Connection.credentials/0),
       service: Keyword.get(opts, :service, &Connection.pds_url/0),
       manager: nil,
       monitor: nil
     }}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    case current_session(state) do
      {:ok, session} -> {:reply, {:ok, public_identity(session)}, state}
      :disconnected -> do_connect(state)
    end
  end

  def handle_call(:session, _from, state) do
    case current_session(state) do
      {:ok, session} -> {:reply, {:ok, session}, state}
      :disconnected -> do_connect(state, true)
    end
  end

  def handle_call(:status, _from, state) do
    status =
      case current_session(state) do
        {:ok, session} -> Map.put(public_identity(session), :connected?, true)
        :disconnected -> %{connected?: false, did: nil, handle: nil}
      end

    {:reply, status, state}
  end

  def handle_call(:disconnect, _from, state) do
    {:reply, :ok, stop_manager(state)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor: ref} = state) do
    {:noreply, %{state | manager: nil, monitor: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp do_connect(state, return_session? \\ false) do
    with {:ok, credentials} <- state.credentials.(),
         {:ok, service} <- state.service.(),
         {:ok, session} <-
           state.transport.login(credentials.identifier, credentials.password, service: service),
         {:ok, manager} <- start_manager(state.supervisor, session) do
      monitor = Process.monitor(manager)
      next = %{state | manager: manager, monitor: monitor}
      reply = if return_session?, do: {:ok, session}, else: {:ok, public_identity(session)}
      {:reply, reply, next}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp start_manager(supervisor, session) do
    child =
      Supervisor.child_spec(
        {ProtoRune.SessionManager, session: session},
        id: {:delvetown_session, System.unique_integer([:positive])},
        restart: :temporary
      )

    DynamicSupervisor.start_child(supervisor, child)
  end

  defp current_session(%{manager: manager}) when is_pid(manager) do
    if Process.alive?(manager),
      do: {:ok, ProtoRune.SessionManager.session(manager)},
      else: :disconnected
  catch
    :exit, _reason -> :disconnected
  end

  defp current_session(_state), do: :disconnected

  defp stop_manager(%{manager: nil} = state), do: state

  defp stop_manager(state) do
    if state.monitor, do: Process.demonitor(state.monitor, [:flush])
    _result = DynamicSupervisor.terminate_child(state.supervisor, state.manager)
    %{state | manager: nil, monitor: nil}
  end

  defp public_identity(session) do
    %{did: Map.get(session, :did), handle: Map.get(session, :handle)}
  end
end
