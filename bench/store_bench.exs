defmodule StoreBench do
  @results_dir "bench/results"

  def run do
    Mace.Store.init()
    Process.flag(:trap_exit, true)

    prev_path = latest_save()

    opts =
      [
        time: 3,
        warmup: 1,
        formatters: [Benchee.Formatters.Console],
        save: %{path: timestamped_path(), tag: "store"}
      ]
      |> then(fn o -> if prev_path, do: Keyword.put(o, :load, prev_path), else: o end)

    Benchee.run(benchmarks(), opts)

    File.write!(Path.join(results_dir(), "latest.txt"), timestamped_path())

    if prev_path do
      IO.puts("\nCompared against: #{Path.basename(prev_path)}")
    end
  end

  defp benchmarks do
    %{
      "put (write config)" =>
        {
          fn _ -> Mace.Store.put(:app, :key, :val) end,
          before_each: fn _ -> Mace.Store.delete(self()) end,
          after_each: fn _ -> Mace.Store.delete(self()) end
        },
      "fetch (hit, config on self)" =>
        {
          fn _ -> Mace.Store.fetch(self(), :app, :key) end,
          before_scenario: fn _ -> Mace.Store.put(:app, :key, :val) end,
          after_scenario: fn _ -> Mace.Store.delete(self()) end
        },
      "fetch (miss, cached, ETS lookup)" =>
        {
          fn pid -> Mace.Store.fetch(pid, :app, :miss) end,
          before_scenario: fn _ ->
            pid = spawn(fn -> Process.sleep(:infinity) end)
            Mace.Store.fetch(pid, :app, :miss)
            pid
          end,
          after_scenario: fn pid -> Process.exit(pid, :kill) end
        },
      "fetch (miss, uncached, walks links+monitors)" =>
        {
          fn pid -> Mace.Store.fetch(pid, :app, :miss) end,
          before_scenario: fn _ ->
            Task.async(fn -> Process.sleep(:infinity) end).pid
          end,
          after_scenario: fn pid -> Process.exit(pid, :kill) end
        },
      "fetch (hit, via tree walk to parent)" =>
        {
          fn pid -> Mace.Store.fetch(pid, :app, :key) end,
          before_scenario: fn _ ->
            Mace.Store.put(:app, :key, :val)
            Task.async(fn -> Process.sleep(:infinity) end).pid
          end,
          after_scenario: fn pid ->
            Process.exit(pid, :kill)
            Mace.Store.delete(self())
          end
        },
      "put + delete kv (tombstone)" =>
        {
          fn _ ->
            Mace.Store.put(:app, :key, :val)
            Mace.Store.delete(self(), :app, :key)
          end,
          before_each: fn _ -> Mace.Store.delete(self()) end,
          after_each: fn _ -> Mace.Store.delete(self()) end
        },
      "put + delete all (flush cache)" =>
        {
          fn _ ->
            Mace.Store.put(:app, :key, :val)
            Mace.Store.delete(self())
          end,
          before_each: fn _ -> Mace.Store.delete(self()) end,
          after_each: fn _ -> Mace.Store.delete(self()) end
        },
      "mixed (3 puts, 4 fetches, 1 delete)" =>
        {
          fn _ ->
            Mace.Store.put(:a1, :k1, 1)
            Mace.Store.put(:a1, :k2, 2)
            Mace.Store.put(:a2, :k1, 3)
            Mace.Store.fetch(self(), :a1, :k1)
            Mace.Store.fetch(self(), :a1, :k2)
            Mace.Store.fetch(self(), :a2, :k1)
            Mace.Store.fetch(self(), :no, :k1)
            Mace.Store.delete(self())
          end,
          before_each: fn _ -> Mace.Store.delete(self()) end,
          after_each: fn _ -> Mace.Store.delete(self()) end
        }
    }
  end

  defp results_dir, do: Path.join(File.cwd!(), @results_dir)

  defp timestamped_path do
    File.mkdir_p!(results_dir())
    ts = NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
    Path.join(results_dir(), String.replace(ts, " ", "T") <> ".benchee")
  end

  defp latest_save do
    latest_txt = Path.join(results_dir(), "latest.txt")

    if File.exists?(latest_txt) do
      path = File.read!(latest_txt) |> String.trim()

      if File.exists?(path) do
        path
      end
    end
  end
end

StoreBench.run()
