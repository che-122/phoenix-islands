# Frontend Pipeline Code Review

## Critical Bugs

### P0 — `data-lazy="false"` Is Truthy in HTML

```heex
<!-- island_component.ex -->
<island-root
  data-module={@module}
  data-lazy={@lazy}
  ...
```

When `@lazy` is `false`, this renders `data-lazy="false"`. But in the client:

```ts
// island_root.ts
if (this.hasAttribute('data-lazy')) {
  await visible({ element: this })
}
```

`hasAttribute` checks for **presence**, not value — so `data-lazy="false"` triggers lazy loading.

**Fix:** Use `nil` to omit the attribute when falsy:

```heex
<island-root
  data-module={@module}
  data-lazy={@lazy || nil}
  data-media={@media}
  data-props={@json}
>{@ssr_html}</island-root>
```

---

## High Priority Issues

### P1 — GenServer.call Timeout < Internal Timer

`render/2` uses the default `GenServer.call` timeout of 5 seconds:

```elixir
def render(module, props) do
  GenServer.call(__MODULE__, {:render, %{module: module, props: props}})
end
```

But the internal request timer is 10 seconds:

```elixir
timer_ref = Process.send_after(self(), {:request_timeout, id}, 10_000)
```

The `GenServer.call` will timeout at 5s and crash the caller while the 10s timer is still ticking — leaving an orphaned pending entry. Either align them or set an explicit timeout:

```elixir
def render(module, props) do
  GenServer.call(__MODULE__, {:render, %{module: module, props: props}}, 15_000)
end
```

---

### P1 — Deprecated `performance.navigation` API

```ts
// island_root.ts
if (
  window.performance?.navigation?.type ===
    performance.navigation.TYPE_RELOAD ||
  window.performance?.navigation?.type ===
    performance.navigation.TYPE_BACK_FORWARD
)
```

`performance.navigation` is deprecated. Use `PerformanceNavigationTiming`:

```ts
const navEntry = performance.getEntriesByType("navigation")[0] as PerformanceNavigationTiming | undefined;
if (navEntry && (navEntry.type === "reload" || navEntry.type === "back_forward")) {
  // reset inputs...
}
```

---

### P1 — No Svelte Component Cleanup on Media Unmatch

```ts
// island_root.ts
this.cleanupMediaListener = media({
  query,
  onMatch: async () => await this.hydrate(),
  onUnmatch: () => (this.innerHTML = ''),
})
```

When the media query unmatches, the DOM is cleared with `innerHTML = ''`, but the Svelte component instance is never properly destroyed (`unmount()`). This leaks event listeners and subscriptions. Track the mounted component and call its destroy/unmount method on unmatch.

---

## Medium Priority Issues

### P2 — Fragile Relative Worker Path

```elixir
# config.exs
config :selfservice_test, SelfServiceWeb.IslandSsrWorker,
  worker_path: "priv/static/assets/ssr/worker.js",
  runtime: "node"
```

This relative path depends on the CWD of the BEAM process, which can differ between dev, releases, and deployment. Resolve it in `init/1`:

```elixir
def init(_opts) do
  config = Application.get_env(:selfservice_test, __MODULE__, [])
  worker_path = Path.join(:code.priv_dir(:selfservice_test), "static/assets/ssr/worker.js")

  state = %{@initial_state | worker_path: worker_path, runtime: Keyword.fetch!(config, :runtime)}
  {:ok, start_port!(state)}
end
```

---

### P2 — Single Node Process Bottleneck

The GenServer manages a single Node.js process via an Erlang Port. Since `island/1` is a function component called during template rendering, every SSR'd island blocks the page render synchronously. Multiple islands on a page render sequentially through this single process.

**Suggestions:**

- Consider a pool of Node workers via `NimblePool` or a simple round-robin GenServer pool
- Consider a batch API: send all render requests for a page at once, then collect results
- For production workloads, a single process will become a serialization bottleneck

---

### P2 — No Crash-Loop Protection for Port Restarts

```elixir
def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
  Logger.info("External exit: :exit_status: #{status}")

  for {_id, %{from: from}} <- state.pending do
    GenServer.reply(from, {:error, :worker_crashed})
  end

  {:noreply, %{state | port: nil, pending: %{}, buffer: ""}}
end
```

If Node keeps crashing, the GenServer restarts it on every `render/2` call with no backoff. Consider letting the GenServer itself crash so the OTP supervisor can enforce backoff via `max_restarts`/`max_seconds`:

```elixir
def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
  Logger.error("Node worker exited with status #{status}")

  for {_id, %{from: from}} <- state.pending do
    GenServer.reply(from, {:error, :worker_crashed})
  end

  {:stop, {:worker_exited, status}, %{state | port: nil, pending: %{}, buffer: ""}}
end
```

---

### P2 — GenServer State Should Be a Struct

```elixir
@initial_state %{
  id: nil,
  port: nil,
  next_id: 1,
  buffer: "",
  pending: %{},
  worker_path: nil,
  runtime: nil
}
```

Using a plain map means no compile-time key checks. The `id` field also appears unused. Define a struct:

```elixir
defmodule SelfServiceWeb.IslandSsrWorker do
  use GenServer

  defstruct [:port, :worker_path, :runtime, next_id: 1, buffer: "", pending: %{}]

  # Pattern match with %__MODULE__{} throughout
end
```

This gives compile warnings for misspelled keys and better documentation of the state shape.

---

## Lower Priority Issues

### P3 — Dead Commented-Out Code in `app.ts`

About 70% of `app.ts` is commented-out boilerplate (LiveView, LiveSocket, live_reload). Strip it down to what's actually used. You can always reference the Phoenix generator for the LiveView boilerplate if needed later.

---

### P3 — Module Placement

`SelfServiceWeb.IslandSsrWorker` lives in the web namespace but it's not a web concern — it's runtime infrastructure. Consider moving it to `SelfService.IslandSsrWorker` or `SelfService.SSR.Worker`.

Similarly, `island_component.ex` defines a single function component `island/1`. Consider either:

- Renaming to `island_components.ex` (plural, matching Phoenix convention)
- Or folding `island/1` into `core_components.ex` since it's imported globally via `html_helpers`

---

### P3 — Virtual Module Watch Invalidation

When a new `.svelte` file is added to `js/components/`, the `virtual:components` module won't regenerate until esbuild restarts. esbuild's `onLoad` for virtual modules doesn't automatically re-trigger on filesystem changes. Consider adding `watchFiles` or `watchDirs` to the plugin result to invalidate the cache.

---

### P3 — Flat Component Directory

All components must live directly in `js/components/`. Consider supporting nested directories for organization (e.g. `components/ui/Button.svelte`, `components/features/TodoList.svelte`). Be aware of naming collisions if you do — use relative paths as registry keys.

---

### P3 — TypeScript Typing for Virtual Module

```ts
// env.d.ts
declare module 'virtual:components' {
    const components: Record<string, any>;
    export default components;
}
```

The `any` type provides no IDE assistance. Consider:

```ts
declare module 'virtual:components' {
  type ComponentImporter = () => Promise<{ default: typeof import('svelte').SvelteComponent }>;
  const components: Record<string, ComponentImporter>;
  export default components;
}
```

---

### P3 — File/Directory Naming

The `islands/` directory contains island **infrastructure**, not the islands themselves (those are in `components/`). Consider renaming for clarity:

```
assets/js/
├── app.ts
├── components/           # Svelte island components
├── runtime/              # Island runtime infrastructure
│   ├── hydration.ts      # Web component (was island_root.ts)
│   └── ssr_worker.ts     # Node SSR process (was ssr/worker.ts)
```

---

## Summary Table

| Priority | Issue | Location |
|----------|-------|----------|
| **P0** | `data-lazy="false"` is truthy in HTML | `island_component.ex:19` |
| **P1** | GenServer.call timeout (5s) < internal timer (10s) | `island_ssr_worker.ex:24` |
| **P1** | Deprecated `performance.navigation` API | `island_root.ts:11-14` |
| **P1** | No Svelte component cleanup on media unmatch | `island_root.ts:128` |
| **P2** | Fragile relative worker path | `config.exs:28` |
| **P2** | Single Node process bottleneck | Architecture |
| **P2** | No crash-loop protection for port restarts | `island_ssr_worker.ex` |
| **P2** | GenServer state should be a struct | `island_ssr_worker.ex` |
| **P3** | Dead commented-out code in `app.ts` | `app.ts` |
| **P3** | Module placement (`IslandSsrWorker` in Web) | File structure |
| **P3** | Virtual module watch invalidation | `build.js` |
| **P3** | Flat component directory | `build.js` |
| **P3** | Weak TypeScript typing for virtual module | `env.d.ts` |
| **P3** | Ambiguous `islands/` directory naming | File structure |
