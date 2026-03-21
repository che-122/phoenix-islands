defmodule Dashboard.RSS.Diagnostics do
  @moduledoc """
  Stores lightweight scheduler diagnostics for the debug panel.
  """

  use GenServer

  @type summary :: %{
          due_count: non_neg_integer(),
          ok_count: non_neg_integer(),
          error_count: non_neg_integer(),
          exit_count: non_neg_integer(),
          error_samples: [map()]
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def snapshot do
    scheduler_running? = Process.whereis(Dashboard.RSS.Scheduler) != nil

    case Process.whereis(__MODULE__) do
      nil ->
        %{running?: false, scheduler_running?: scheduler_running?}

      _pid ->
        __MODULE__
        |> GenServer.call(:snapshot)
        |> Map.put(:scheduler_running?, scheduler_running?)
    end
  end

  def record_update(started_at, finished_at, summary, error \\ nil) do
    GenServer.cast(__MODULE__, {:record_update, started_at, finished_at, summary, error})
  end

  def record_reprobe(started_at, finished_at, summary) do
    GenServer.cast(__MODULE__, {:record_reprobe, started_at, finished_at, summary})
  end

  @impl true
  def init(state) do
    {:ok, Map.put(state, :started_at, DateTime.utc_now())}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, Map.put(state, :running?, true), state}
  end

  @impl true
  def handle_cast({:record_update, started_at, finished_at, summary, error}, state) do
    state =
      state
      |> Map.put(:last_update_started_at, started_at)
      |> Map.put(:last_update_finished_at, finished_at)
      |> Map.put(:last_update_summary, summary)
      |> Map.put(:last_update_error, error)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_reprobe, started_at, finished_at, summary}, state) do
    state =
      state
      |> Map.put(:last_reprobe_started_at, started_at)
      |> Map.put(:last_reprobe_finished_at, finished_at)
      |> Map.put(:last_reprobe_summary, summary)

    {:noreply, state}
  end
end
