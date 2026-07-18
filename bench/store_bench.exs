defmodule StoreBench do
  @iterations 10_000
  @warmup 1_000

  def run do
    Mace.Store.init()
    Process.flag(:trap_exit, true)

    IO.puts("=== Mace.Store Benchmarks (#{@iterations} iterations each) ===\n")

    bench_put()
    bench_fetch_hit_self()
    bench_fetch_miss_cached()
    bench_fetch_miss_uncached()
    bench_fetch_hit_tree_walk()
    bench_delete_kv()
    bench_delete_all()
    bench_mixed()
  end

  # ---- put ----

  defp bench_put do
    clean()

    warmup(fn -> Mace.Store.put(:app, :key, :val) end)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations, do: Mace.Store.put(:app, :key, :val)
    end)

    clean()
    report("put (write config)", time)
  end

  # ---- fetch: hit on self ----

  defp bench_fetch_hit_self do
    clean()
    Mace.Store.put(:app, :key, :val)

    warmup(fn -> Mace.Store.fetch(self(), :app, :key) end)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations, do: Mace.Store.fetch(self(), :app, :key)
    end)

    clean()
    report("fetch (hit, config on self)", time)
  end

  # ---- fetch: cached miss ----

  defp bench_fetch_miss_cached do
    clean()
    pid = spawn(fn -> Process.sleep(:infinity) end)

    # First call walks (empty links), caches the miss
    Mace.Store.fetch(pid, :app, :miss)

    warmup(fn -> Mace.Store.fetch(pid, :app, :miss) end)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations, do: Mace.Store.fetch(pid, :app, :miss)
    end)

    Process.exit(pid, :kill)
    clean()
    report("fetch (miss, cached, ETS lookup)", time)
  end

  # ---- fetch: uncached miss ----

  defp bench_fetch_miss_uncached do
    clean()
    child = Task.async(fn -> Process.sleep(:infinity) end).pid

    {time, _} = :timer.tc(fn ->
      for i <- 1..@iterations do
        Mace.Store.fetch(child, :app, :"u#{i}")
      end
    end)

    Process.exit(child, :kill)
    clean()
    report("fetch (miss, uncached, walks links+monitors)", time)
  end

  # ---- fetch: hit via tree walk ----

  defp bench_fetch_hit_tree_walk do
    clean()
    Mace.Store.put(:app, :key, :val)
    child = Task.async(fn -> Process.sleep(:infinity) end).pid

    warmup(fn -> Mace.Store.fetch(child, :app, :key) end)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations, do: Mace.Store.fetch(child, :app, :key)
    end)

    Process.exit(child, :kill)
    clean()
    report("fetch (hit, via tree walk to parent)", time)
  end

  # ---- delete kv ----

  defp bench_delete_kv do
    clean()

    warmup(fn ->
      Mace.Store.put(:app, :key, :val)
      Mace.Store.delete(self(), :app, :key)
    end)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations do
        Mace.Store.put(:app, :key, :val)
        Mace.Store.delete(self(), :app, :key)
      end
    end)

    clean()
    report("put + delete kv (tombstone)", time)
  end

  # ---- delete all ----

  defp bench_delete_all do
    clean()

    warmup(fn ->
      Mace.Store.put(:app, :key, :val)
      Mace.Store.delete(self())
    end)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations do
        Mace.Store.put(:app, :key, :val)
        Mace.Store.delete(self())
      end
    end)

    clean()
    report("put + delete all (flush cache)", time)
  end

  # ---- mixed ----

  defp bench_mixed do
    clean()

    mixed = fn ->
      Mace.Store.put(:a1, :k1, 1)
      Mace.Store.put(:a1, :k2, 2)
      Mace.Store.put(:a2, :k1, 3)
      Mace.Store.fetch(self(), :a1, :k1)
      Mace.Store.fetch(self(), :a1, :k2)
      Mace.Store.fetch(self(), :a2, :k1)
      Mace.Store.fetch(self(), :no, :k1)
      Mace.Store.delete(self())
    end

    warmup(mixed)

    {time, _} = :timer.tc(fn ->
      for _ <- 1..@iterations, do: mixed.()
    end)

    clean()
    report("mixed (3 puts, 4 fetches, 1 delete)", time)
  end

  # ---- helpers ----

  defp clean, do: Mace.Store.delete(self())
  defp warmup(fun), do: for(_ <- 1..@warmup, do: fun.())

  defp report(name, time_us) do
    per_ns = time_us / @iterations * 1000
    IO.puts("#{String.pad_trailing(name, 50)} #{Float.round(time_us / 1000, 1)} ms  |  #{format_ns(per_ns)} / op")
  end

  defp format_ns(ns) when ns >= 100_000, do: "#{Float.round(ns / 1000, 1)} µs"
  defp format_ns(ns), do: "#{Float.round(ns, 0)} ns"
end

StoreBench.run()
EOF
