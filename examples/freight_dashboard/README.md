# Freight Dashboard — mace Expand/Contract Demo

A Phoenix LiveView freight dashboard demonstrating
[mace](https://github.com/pmonson711/mace)'s expand/contract pattern
for feature-flag-driven migrations.

## What it Shows

Two dashboard widgets — **Shipment Tracker** and **Fleet Status** — each
with a "legacy" and "new" implementation. The active implementation is
controlled by `Application.get_env`. A flag manager lets you toggle
between them in real time.

The tests use mace to run both implementations in parallel, isolated
`describe` blocks with no config leaks.

## Running Locally

```bash
mix deps.get
mix phx.server
```

Open http://localhost:4000. Toggle the feature flags and watch the
widgets switch between legacy and new rendering.

## Running Tests

```bash
mix test
```

All tests run with `async: true`. Each `describe` block gets its own
isolated config via mace.

## The Expand/Contract Pattern

This project demonstrates how mace enables safe feature migration through
four phases:

### 1. Starting State

We have two widgets, each with a single implementation. Config points to
the legacy modules:

```elixir
# config/config.exs
config :freight_dashboard, :shipment_tracker, FreightDashboard.ShipmentTracker.Legacy
config :freight_dashboard, :fleet_status, FreightDashboard.FleetStatus.Legacy
```

Tests only cover the legacy path.

### 2. Expand

We build the new implementations (`ShipmentTracker.New`, `FleetStatus.New`)
behind feature flags. Tests gain a second `describe` block for each widget
that sets the flag to the new implementation:

```elixir
describe "with legacy tracker" do
  setup do
    Mace.put_config(:freight_dashboard, :shipment_tracker,
      FreightDashboard.ShipmentTracker.Legacy)
  end

  test "renders shipments in a table" do
    # ...
  end
end

describe "with new tracker" do
  setup do
    Mace.put_config(:freight_dashboard, :shipment_tracker,
      FreightDashboard.ShipmentTracker.New)
  end

  test "renders shipments in timeline cards" do
    # ...
  end
end
```

Both describe blocks run with `async: true` — mace gives each its own
isolated view of `Application.get_env`. No global config mutation needed.

### 3. Ship

Deploy with the flag on. Both old and new code paths are tested and
production-ready. The flag lets you roll out the new implementation
gradually or revert instantly if issues arise.

### 4. Contract

Once the new implementations are proven in production:

1. Delete the legacy modules (`Legacy` files)
2. Remove the legacy `describe` blocks from tests
3. Remove the feature flag from `config.exs`
4. Point `ShipmentTracker.render/1` directly at the new implementation

The flag served its purpose. The codebase is clean again.

### Why This Is Hard Without mace

Without per-test config isolation:

- Tests can't run `async: true` — `Application.put_env` mutations would
  leak between concurrent tests
- Each test needs manual `Application.put_env`/`Application.delete_env`
  cleanup in `on_exit`
- A test failure that skips cleanup poisons subsequent tests
- You can't test both the old and new code path in the same test suite
  without complex setup/teardown gymnastics

mace removes all of that. Tests behave as if each one has its own
private `config.exs`.

## Project Structure

```
lib/
  freight_dashboard/
    shipment_tracker.ex         # Behaviour + dispatch
    shipment_tracker/
      legacy.ex                 # <table> implementation
      new.ex                    # Timeline card implementation
    fleet_status.ex             # Behaviour + dispatch
    fleet_status/
      legacy.ex                 # Plain list implementation
      new.ex                    # Status card implementation
  freight_dashboard_web/
    live/
      dashboard_live.ex         # Main page, mounts widgets + flag manager
      flag_manager_live.ex      # Toggle UI component
test/
  freight_dashboard/
    shipment_tracker_test.exs   # Tests both implementations with mace
    fleet_status_test.exs       # Tests both implementations with mace
  freight_dashboard_web/
    live/
      dashboard_live_test.exs   # Integration test
```

## Key mace API Used

| Function | Purpose |
|---|---|
| `Mace.Store.init/0` | Initialize config store in `test_helper.exs` |
| `Mace.Mock.install/0` | Enable `Application.get_env` interception (called once in `test_helper.exs`) |
| `Mace.put_config/3` | Set per-test config override |
