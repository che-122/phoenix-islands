defmodule Dashboard.RSS.Scheduler do
  use GenServer

  alias Dashboard.RSS.IngestService

  # 60 seconds base tick
  @interval 60 * 1000

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
    IngestService.update_feeds()

    schedule_next_update()

    {:noreply, state}
  end

  def handle_info(:reprobe, state) do
    Dashboard.RSS.list_feed(:suspended_for_reprobe)
    |> Enum.each(&IngestService.update_pipeline/1)

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
