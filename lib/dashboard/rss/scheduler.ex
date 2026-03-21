defmodule Dashboard.RSS.Scheduler do
  use GenServer

  alias Dashboard.RSS.BatchSummary
  alias Dashboard.RSS.Diagnostics
  alias Dashboard.RSS.IngestService

  # 10 seconds base tick
  @interval 10 * 1000

  # Check suspended feeds for reprobe every 6 hours
  @reprobe_interval 6 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_next_update()
    schedule_reprobe()

    {:ok, state}
  end

  def handle_info(:update, state) do
    started_at = DateTime.utc_now()

    try do
      runs = IngestService.update_feeds()
      summary = BatchSummary.build(runs)
      Diagnostics.record_update(started_at, DateTime.utc_now(), summary, nil)
    rescue
      exception ->
        Diagnostics.record_update(
          started_at,
          DateTime.utc_now(),
          BatchSummary.build([]),
          Exception.message(exception)
        )
    catch
      kind, reason ->
        Diagnostics.record_update(
          started_at,
          DateTime.utc_now(),
          BatchSummary.build([]),
          "#{inspect(kind)}: #{inspect(reason)}"
        )
    end

    schedule_next_update()

    {:noreply, state}
  end

  def handle_info(:reprobe, state) do
    started_at = DateTime.utc_now()

    suspended_due = Dashboard.RSS.list_feed(:suspended_for_reprobe)
    results = Enum.map(suspended_due, &IngestService.update_pipeline/1)

    Diagnostics.record_reprobe(started_at, DateTime.utc_now(), %{
      due_count: length(suspended_due),
      ok_count: Enum.count(results, &match?({:ok, _}, &1))
    })

    schedule_reprobe()

    {:noreply, state}
  end

  defp schedule_next_update do
    jittered = @interval + :rand.uniform(max(div(@interval, 10), 1))
    Process.send_after(self(), :update, jittered)
  end

  defp schedule_reprobe do
    jittered = @reprobe_interval + :rand.uniform(max(div(@reprobe_interval, 10), 1))
    Process.send_after(self(), :reprobe, jittered)
  end
end
