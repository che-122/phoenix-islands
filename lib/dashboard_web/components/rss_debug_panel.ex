defmodule DashboardWeb.Components.RSSDebugPanel do
  @moduledoc """
  Debug panel for RSS scheduler/feed state.
  """

  use DashboardWeb, :html

  attr :selected_feed, :any, default: nil

  def panel(assigns) do
    assigns = assign(assigns, :diagnostics, Dashboard.RSS.Diagnostics.snapshot())

    ~H"""
    <div
      id="rss-debug-panel"
      data-debug-panel
      class="hidden absolute right-4 bottom-4 z-50 w-[24rem] max-w-[calc(100vw-2rem)] rounded-2xl border border-base-content/20 bg-base-100/95 p-4 text-xs text-base-content shadow-2xl backdrop-blur"
    >
      <div class="flex items-center justify-between">
        <h2 class="font-semibold tracking-wide">RSS Debug</h2>
        <span class="rounded-md border border-base-300 px-2 py-0.5 text-[10px] uppercase tracking-[0.14em] text-base-content/70">
          localStorage.debug
        </span>
      </div>
      <p class="mt-2 text-[11px] leading-relaxed text-base-content/70">
        Visible only when `localStorage.getItem("debug") === "true"`.
      </p>
      <dl class="mt-3 space-y-1.5 rounded-xl border border-base-300 bg-base-200/50 p-3">
        <div class="grid grid-cols-[7rem_1fr] gap-2">
          <dt class="text-base-content/60">scheduler</dt>
          <dd class="font-medium">
            {if(@diagnostics[:scheduler_running?], do: "running", else: "down")}
          </dd>
        </div>
        <div class="grid grid-cols-[7rem_1fr] gap-2">
          <dt class="text-base-content/60">diagnostics</dt>
          <dd class="font-medium">{if(@diagnostics.running?, do: "running", else: "down")}</dd>
        </div>
        <div class="grid grid-cols-[7rem_1fr] gap-2">
          <dt class="text-base-content/60">last_tick</dt>
          <dd class="truncate">{inspect(@diagnostics[:last_update_finished_at])}</dd>
        </div>
        <div class="grid grid-cols-[7rem_1fr] gap-2">
          <dt class="text-base-content/60">due/ok</dt>
          <dd>
            {inspect(get_in(@diagnostics, [:last_update_summary, :due_count]))}/{inspect(
              get_in(@diagnostics, [:last_update_summary, :ok_count])
            )}
          </dd>
        </div>
        <div class="grid grid-cols-[7rem_1fr] gap-2">
          <dt class="text-base-content/60">errors</dt>
          <dd>{inspect(get_in(@diagnostics, [:last_update_summary, :error_count]))}</dd>
        </div>
        <div class="grid grid-cols-[7rem_1fr] gap-2">
          <dt class="text-base-content/60">exits</dt>
          <dd>{inspect(get_in(@diagnostics, [:last_update_summary, :exit_count]))}</dd>
        </div>
        <%= if @diagnostics[:last_update_error] do %>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">tick_error</dt>
            <dd class="truncate">{@diagnostics[:last_update_error]}</dd>
          </div>
        <% end %>
        <%= if sample = List.first(get_in(@diagnostics, [:last_update_summary, :error_samples]) || []) do %>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">sample_feed</dt>
            <dd class="truncate">{sample.title}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">sample_err</dt>
            <dd class="truncate">{sample.reason}</dd>
          </div>
        <% end %>
      </dl>

      <%= if @selected_feed do %>
        <dl class="mt-3 space-y-1.5 rounded-xl border border-base-300 bg-base-200/50 p-3">
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">title</dt>
            <dd class="truncate font-medium">{@selected_feed.title}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">status</dt>
            <dd class="font-medium">{@selected_feed.status}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">next_fetch</dt>
            <dd class="truncate">{inspect(@selected_feed.next_fetch)}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">last_fetched</dt>
            <dd class="truncate">{inspect(@selected_feed.last_fetched_at)}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">http_status</dt>
            <dd>{inspect(@selected_feed.last_http_status)}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">error_count</dt>
            <dd>{@selected_feed.error_count || 0}</dd>
          </div>
          <div class="grid grid-cols-[7rem_1fr] gap-2">
            <dt class="text-base-content/60">reason</dt>
            <dd class="truncate">{@selected_feed.suspension_reason || "-"}</dd>
          </div>
        </dl>
      <% else %>
        <p class="mt-3 rounded-xl border border-dashed border-base-300 bg-base-200/50 px-3 py-2 text-base-content/70">
          Select a feed to inspect polling state.
        </p>
      <% end %>
    </div>
    """
  end
end
