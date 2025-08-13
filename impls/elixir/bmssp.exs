#!/usr/bin/env elixir
# Simple BMSSP (bounded multi-source Dijkstra) implementation printing JSON lines.

defmodule BMSSP do
  def parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          graph: :string,
          rows: :integer,
          cols: :integer,
          n: :integer,
          p: :float,
          k: :integer,
          B: :integer,
          trials: :integer,
          seed: :integer,
          maxw: :integer
        ]
      )

    opts
  end

  def idx(r, c, cols), do: r * cols + c

  def make_grid(rows, cols, maxw) do
    n = rows * cols
    adj0 = for _ <- 1..n, do: []

    adj =
      Enum.reduce(0..(rows - 1), adj0, fn r, acc ->
        Enum.reduce(0..(cols - 1), acc, fn c, acc2 ->
          u = idx(r, c, cols)

          acc3 =
            if r + 1 < rows do
              v = idx(r + 1, c, cols)
              w = :rand.uniform(maxw)

              acc2
              |> List.update_at(u, fn l -> [{v, w} | l] end)
              |> List.update_at(v, fn l -> [{u, w} | l] end)
            else
              acc2
            end

          if c + 1 < cols do
            v = idx(r, c + 1, cols)
            w = :rand.uniform(maxw)

            acc3
            |> List.update_at(u, fn l -> [{v, w} | l] end)
            |> List.update_at(v, fn l -> [{u, w} | l] end)
          else
            acc3
          end
        end)
      end)

    {n, adj}
  end

  def make_er(n, p, maxw) do
    adj0 = for _ <- 1..n, do: []

    adj =
      Enum.reduce(0..(n - 1), adj0, fn u, acc ->
        Enum.reduce((u + 1)..(n - 1), acc, fn v, acc2 ->
          if :rand.uniform() < p do
            w = :rand.uniform(maxw)

            acc2
            |> List.update_at(u, fn l -> [{v, w} | l] end)
            |> List.update_at(v, fn l -> [{u, w} | l] end)
          else
            acc2
          end
        end)
      end)

    {n, adj}
  end

  def make_ba(n, m0, m, maxw) do
    adj0 = for _ <- 1..n, do: []
    # initial chain of m0
    adj1 =
      Enum.reduce(0..(m0 - 2), adj0, fn u, acc ->
        w = :rand.uniform(maxw)

        acc
        |> List.update_at(u, fn l -> [{u + 1, w} | l] end)
        |> List.update_at(u + 1, fn l -> [{u, w} | l] end)
      end)

    deg = :array.new(n, default: 0)

    deg =
      Enum.reduce(0..(m0 - 2), deg, fn u, d ->
        d |> :array.set(u, :array.get(u, d) + 1) |> :array.set(u + 1, :array.get(u + 1, d) + 1)
      end)

    sumdeg = Enum.reduce(0..(n - 1), 0, fn i, s -> s + (:array.get(i, deg) || 0) end)

    Enum.reduce(m0..(n - 1), {adj1, deg, sumdeg}, fn u, {adj, d, sd} ->
      choose = fn ->
        r = :rand.uniform() * max(sd, 1)

        Enum.reduce_while(0..(u - 1), 0, fn v, acc ->
          acc2 = acc + :array.get(v, d)
          if acc2 >= r, do: {:halt, v}, else: {:cont, acc2}
        end)
      end

      {adj2, d2, sd2, _} =
        Enum.reduce(1..m, {adj, d, sd, MapSet.new()}, fn _, {a, dd, sdd, seen} ->
          v = choose.()

          if v == u or MapSet.member?(seen, v) do
            {a, dd, sdd, seen}
          else
            w = :rand.uniform(maxw)

            a2 =
              a
              |> List.update_at(u, fn l -> [{v, w} | l] end)
              |> List.update_at(v, fn l -> [{u, w} | l] end)

            dd2 =
              dd |> :array.set(u, :array.get(u, dd) + 1) |> :array.set(v, :array.get(v, dd) + 1)

            {a2, dd2, sdd + 2, MapSet.put(seen, v)}
          end
        end)

      {adj2, d2, sd2}
    end)
    |> then(fn {adjf, _, _} -> {n, adjf} end)
  end

  def pick_sources(n, k) do
    do_pick(MapSet.new(), n, k, [])
  end

  defp do_pick(seen, n, k, acc) when length(acc) == k, do: Enum.reverse(acc)

  defp do_pick(seen, n, k, acc) do
    if MapSet.size(seen) == n do
      Enum.reverse(acc)
    else
      s = :rand.uniform(n) - 1

      if MapSet.member?(seen, s),
        do: do_pick(seen, n, k, acc),
        else: do_pick(MapSet.put(seen, s), n, k, [{s, 0} | acc])
    end
  end

  def bmssp({n, adj}, sources, b) do
    dist = :array.new(n, default: :infinity)
    heap = :gb_sets.empty()

    {dist, heap} =
      Enum.reduce(sources, {dist, heap}, fn {s, d0}, {di, he} ->
        if d0 < b do
          di2 = :array.set(s, d0, di)
          {di2, :gb_sets.add({d0, s}, he)}
        else
          {di, he}
        end
      end)

    edges_scanned = 0
    pushes = 0
    explored = 0
    bprime = :infinity

    loop = fn loop, dist, heap, edges_scanned, pushes, explored, bprime ->
      case :gb_sets.is_empty(heap) do
        true ->
          {dist, explored, edges_scanned, pushes, bprime}

        false ->
          {{d, v}, heap2} = :gb_sets.take_smallest(heap)
          cur = :array.get(v, dist)

          cond do
            cur != d ->
              loop.(loop, dist, heap2, edges_scanned, pushes, explored, bprime)

            d >= b ->
              {dist, explored, edges_scanned, pushes, min(bprime, d)}

            true ->
              explored2 = explored + 1

              {dist3, heap3, edges_scanned3, pushes3, bprime3} =
                Enum.reduce(Enum.at(adj, v), {dist, heap2, edges_scanned, pushes, bprime}, fn {to,
                                                                                               w},
                                                                                              {di,
                                                                                               he,
                                                                                               es,
                                                                                               pu,
                                                                                               bp} ->
                  es2 = es + 1
                  nd = d + w
                  cur_to = :array.get(to, di)

                  cond do
                    nd < b and (cur_to == :infinity or nd < cur_to) ->
                      di2 = :array.set(to, nd, di)
                      {di2, :gb_sets.add({nd, to}, he), es2, pu + 1, bp}

                    nd >= b and (bp == :infinity or nd < bp) ->
                      {di, he, es2, pu, nd}

                    true ->
                      {di, he, es2, pu, bp}
                  end
                end)

              loop.(loop, dist3, heap3, edges_scanned3, pushes3, explored2, bprime3)
          end
      end
    end

    loop.(loop, dist, heap, edges_scanned, pushes, explored, bprime)
  end

  def mem_bytes(n, m), do: m * 16 + n * 16
end

# Main
opts = BMSSP.parse_args(System.argv())
trials = opts[:trials] || 1
seed = opts[:seed] || 1
k = opts[:k] || 1
b = (opts[:B] || 0) |> Kernel.*(1)

Enum.each(0..(trials - 1), fn t ->
  :rand.seed(:exs1024, {seed + t, seed + t + 1, seed + t + 2})

  {n, adj} =
    case opts[:graph] do
      "grid" -> BMSSP.make_grid(opts[:rows], opts[:cols], opts[:maxw] || 100)
      "er" -> BMSSP.make_er(opts[:n], opts[:p] || 0.0, opts[:maxw] || 100)
      "ba" -> BMSSP.make_ba(opts[:n], opts[:m0] || 5, opts[:m] || 5, opts[:maxw] || 100)
      _ -> System.halt(0)
    end

  sources = BMSSP.pick_sources(n, k)
  t0 = System.monotonic_time(:nanosecond)
  {_, explored, edges_scanned, pushes, bprime} = BMSSP.bmssp({n, adj}, sources, b)
  t1 = System.monotonic_time(:nanosecond)
  m = Enum.reduce(adj, 0, fn l, acc -> acc + length(l) end)
  bpr = if bprime == :infinity, do: b, else: bprime

  json =
    "{" <>
      "\"impl\":\"elixir-bmssp\"," <>
      "\"lang\":\"Elixir\"," <>
      "\"graph\":\"#{opts[:graph]}\"," <>
      "\"n\":#{n}," <>
      "\"m\":#{m}," <>
      "\"k\":#{k}," <>
      "\"B\":#{b}," <>
      "\"seed\":#{seed + t}," <>
      "\"time_ns\":#{t1 - t0}," <>
      "\"popped\":#{explored}," <>
      "\"edges_scanned\":#{edges_scanned}," <>
      "\"heap_pushes\":#{pushes}," <>
      "\"B_prime\":#{bpr}," <>
      "\"mem_bytes\":#{BMSSP.mem_bytes(n, m)}" <>
      "}"

  IO.puts(json)
end)
