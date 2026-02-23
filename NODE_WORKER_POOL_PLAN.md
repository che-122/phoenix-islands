# Node Worker Pool via PartitionSupervisor

Replace the single `IslandSsrWorker` GenServer with a `PartitionSupervisor` that starts N workers, each managing its own Node.js process. Requests are distributed across partitions automatically.

Three files need changes. No new dependencies required — `PartitionSupervisor` is built into Elixir.

## 1. Update the supervision tree

In `lib/selfservice_test/application.ex`, replace the direct worker child with a `PartitionSupervisor`:

```elixir
# Replace:
SelfServiceWeb.IslandSsrWorker,

# With:
{PartitionSupervisor,
 child_spec: SelfServiceWeb.IslandSsrWorker,
 name: SelfServiceWeb.IslandSsrWorker.Pool,
 partitions: Application.get_env(:selfservice_test, SelfServiceWeb.IslandSsrWorker)[:pool_size] || System.schedulers_online()},
```

`System.schedulers_online()` defaults to the number of CPU cores, which is a reasonable default for CPU-bound Node rendering.

## 2. Update the GenServer

In `lib/selfservice_test_web/island_ssr_worker.ex`, two changes:

**`start_link/1`** — Accept and pass through the partition keyword (the PartitionSupervisor passes `name:` via opts):

```elixir
def start_link(opts) do
  name = Keyword.get(opts, :name, __MODULE__)
  GenServer.start_link(__MODULE__, opts, name: name)
end
```

**`render/2`** — Route to a partition instead of the singleton name. `PartitionSupervisor` distributes by hashing `self()` (the caller PID), which naturally spreads concurrent requests across workers:

```elixir
def render(module, props) do
  GenServer.call(
    {:via, PartitionSupervisor, {__MODULE__.Pool, self()}},
    {:render, %{module: module, props: props}},
    15_000
  )
end
```

## 3. Add pool_size config (optional)

In `config/config.exs`, add a `pool_size` key:

```elixir
config :selfservice_test, SelfServiceWeb.IslandSsrWorker,
  worker_path: "priv/static/assets/ssr/worker.js",
  runtime: "node",
  pool_size: 4
```

If omitted, defaults to `System.schedulers_online()`.

## What stays the same

- `island_component.ex` — no changes, it calls `IslandSsrWorker.render/2` which handles routing internally
- `worker.ts` — no changes, each Node process is identical
- `build.js` — no changes, single SSR bundle is reused by all workers
- Templates — no changes

## Routing behavior

`PartitionSupervisor` hashes the caller PID to pick a partition. This means:

- Concurrent requests from different processes (different HTTP requests) spread across workers
- Multiple `island/1` calls within the same request hit the same worker (same PID), which is fine — no cross-worker coordination needed
- If you later add the batch/prefetch optimization, `Task.async` callers would have different PIDs and naturally spread across workers too
