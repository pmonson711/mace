# Mace

Mock Application Config Environment. Gives each test its own isolated view of
`Application.get_env` while preventing leaks and allowing async running of code
that uses the global application config state.

## How It Works

Mace sits between your code and `Application.get_env`. When your test calls
`Mace.put_config(:my_app, :timeout, 100)`, Mace registers that override for the test
process. Any call to `Application.get_env(:my_app, :timeout)` from that process
(or a linked child process) gets the override instead of the real config.

Your production code doesn't change. It still calls `Application.get_env`.
Mace handles the interception transparently.


## Install

```elixir
def deps do
  [{:mace, "~> 0.1", only: [:test]}]
end
```

## Setup

`test/test_helper.exs`:

```elixir
Mace.Store.init()
ExUnit.start()
```

In any test module that needs `Application.get_env` interception, call
`Mace.Mock.install()` once in `setup_all`:

```elixir
defmodule MyModuleTest do
  use ExUnit.Case, async: true

  setup_all do
    Mace.Mock.install()
    :ok
  end
end
```

## Basic Use

```elixir
defmodule TimeoutTest do
  use ExUnit.Case, async: true

  setup_all do
    Mace.Mock.install()
    :ok
  end

  setup do
    Mace.put_config(:my_app, :timeout, 100)
    :ok
  end

  test "handles short timeouts" do
    # MyModule.do_thing() calls Application.get_env(:my_app, :timeout)
    # It sees 100, even though the real config says 5000
    assert MyModule.do_thing() == :ok
  end

  test "handles long timeouts" do
    Mace.put_config(:my_app, :timeout, 50_000)
    assert MyModule.do_thing() == :ok
  end
end
```

Both tests run with `async: true`. Each sees its own timeout value.

## Debugging Failures

When a test fails, knowing the active config is half the battle.
Config cleanup happens automatically when the test process exits, but if
you want a diff on failure, use `Mace.cleanup/1` in `on_exit`:

```elixir
setup context do
  Mace.put_config(:my_app, :timeout, 100)
  on_exit(fn -> Mace.cleanup(context) end)
  :ok
end
```

Then call `Mace.diff/1` in your failure output, or wire up the formatter
to show diffs automatically when tests fail:

```
Test config diff for :my_app:
──────────────────────────────────────────────────
  :timeout:  5000 (default)  →  100 (test)
  :debug:    false (default)  →  true (test)
──────────────────────────────────────────────────
```

## Expand and Contract

Config flags are a good way to evolve code safely — ship the new behavior behind
a flag, test with it on, test with it off, remove the old code when you're
confident. Mace makes this pattern straightforward to test.

Say you're replacing an HTTP client. The real config defaults to the old client:

```elixir
# config/config.exs
config :my_app, :http_client, MyApp.LegacyClient
```

The module reads the config at runtime:

```elixir
defmodule MyApp.HTTP do
  def client do
    Application.get_env(:my_app, :http_client)
  end
end
```

### Expand

Add the new client module. In your test, set the config flag to the new client
for one describe block and the old client for another:

```elixir
describe "with legacy client" do
  setup do
    Mace.put_config(:my_app, :http_client, MyApp.LegacyClient)
  end

  test "makes requests" do
    # hits the old code path
  end
end

describe "with new client" do
  setup do
    Mace.put_config(:my_app, :http_client, MyApp.NewClient)
  end

  test "makes requests" do
    # hits the new code path, same tests
  end
end
```

You now have test coverage for both paths without changing any production config
files. Ship the new client behind the flag. Run in production with the new client
enabled for a subset of traffic. Once you're confident, delete the legacy module
and the flag — the tests for the old path get removed, the ones for the new path
stay.

### What this Looks like in practice

Here's a file upload pipeline being migrated from local disk storage to S3:

```elixir
describe "with local disk storage" do
  setup do
    Mace.put_config(:my_app, :storage_backend, MyApp.LocalStorage)
    Mace.put_config(:my_app, :storage_path, "test/fixtures/uploads")
  end

  test "stores and retrieves files" do
    assert MyApp.Upload.save(file) == :ok
    assert MyApp.Upload.fetch(file.id) == file
  end
end

describe "with S3 storage" do
  setup do
    Mace.put_config(:my_app, :storage_backend, MyApp.S3Storage)
    Mace.put_config(:my_app, :s3_bucket, "test-bucket")
  end

  test "stores and retrieves files" do
    assert MyApp.Upload.save(file) == :ok
    assert MyApp.Upload.fetch(file.id) == file
  end
end
```

Same test, two storage backends. No need to swap config files or mess with
`Application.put_env` globally — each `describe` block gets its own config,
and you can run them both with `async: true`.

## Spawned Processes

Tasks and GenServers started with `start_link` automatically inherit the test's
config via link-walking. Nothing to do:

```elixir
test "task sees test config" do
  Mace.put_config(:my_app, :timeout, 100)

  task = Task.async(fn ->
    Application.get_env(:my_app, :timeout)  # => 100
  end)

  assert Task.await(task) == 100
end
```

If you're doing something exotic that doesn't create a link, use `Mace.task/1`
to explicitly transfer config to the child process.

## A warning about libraries

Config is an application concern, not a library concern. Reading config from a library:

- Creates hidden coupling between the host app's config files and the library's
  behavior
- Makes it impossible for two dependencies of the same app to use the library
  with different configuration
- Breaks when used from escripts or releases where the app isn't started

As such while Mace may be useful for libraries, please be careful with your
design decisions.

Accept configuration as function arguments or module options instead:

```elixir
# Bad: library reads config
defmodule MyLib do
  def timeout, do: Application.get_env(:my_lib, :timeout, 5000)
end

# Good: caller passes config
defmodule MyLib do
  def do_thing(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
  end
end
```

### When Mace still helps

Sometimes configuration is the best option for a library, many time that
indicates a harness that runs your application code or something that help
compose other libraries.

```elixir
defmodule MyLibTest do
  use ExUnit.Case, async: true

  setup_all do
    Mace.Mock.install()
    :ok
  end

  setup do
    Mace.put_config(:my_lib, timeout: 100, retries: 3)
    :ok
  end

  test "respects configured timeout" do
    assert MyLib.do_thing() == :ok
  end
end
```

### When Application config is the right answer

Using Application config in a library is best avoided, but sometimes it is the
right answer. Ecto repos, Phoenix endpoints, and Oban queues all read their
configuration from the host app's Application environment. Each needs config
to be set once globally rather than threaded through every call site, and each
is central enough to its application that there's no ambiguity about which app
owns the config keys.

## API

| Function | |
|---|---|
| `Mace.put_config(app, key, value)` | Set a config override for this test |
| `Mace.put_config(app, keyword_list)` | Set multiple overrides at once |
| `Mace.get_config(app, key)` | Read the active override (returns `{:ok, v}` or `:error`) |
| `Mace.reset()` | Clear all overrides (escape hatch; automatic on test exit) |
| `Mace.diff(app)` | Show diff of overrides vs application defaults |
| `Mace.task(fn)` | Spawn a Task that inherits config |
| `Mace.cleanup(context)` | Record diff + reset; call in `on_exit` for failure debugging |
| `Mace.pid_config()` | Return full config map for this process |
