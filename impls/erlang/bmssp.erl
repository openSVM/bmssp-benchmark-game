-module(bmssp).
-export([main/0, main/1]).

%% Erlang BMSSP minimal CLI printing JSON lines without external deps.

parse_args(Args) -> parse_args(Args, #{}).
parse_args([], Acc) -> Acc;
parse_args(["--graph", G | T], Acc) -> parse_args(T, maps:put(graph, list_to_atom(G), Acc));
parse_args(["--rows", X | T], Acc) -> parse_args(T, maps:put(rows, list_to_integer(X), Acc));
parse_args(["--cols", X | T], Acc) -> parse_args(T, maps:put(cols, list_to_integer(X), Acc));
parse_args(["--n", X | T], Acc) -> parse_args(T, maps:put(n, list_to_integer(X), Acc));
parse_args(["--p", X | T], Acc) -> parse_args(T, maps:put(p, list_to_float(X), Acc));
parse_args(["--m0", X | T], Acc) -> parse_args(T, maps:put(m0, list_to_integer(X), Acc));
parse_args(["--m", X | T], Acc) -> parse_args(T, maps:put(m, list_to_integer(X), Acc));
parse_args(["--k", X | T], Acc) -> parse_args(T, maps:put(k, list_to_integer(X), Acc));
parse_args(["--B", X | T], Acc) -> parse_args(T, maps:put(bound, list_to_integer(X), Acc));
parse_args(["--trials", X | T], Acc) -> parse_args(T, maps:put(trials, list_to_integer(X), Acc));
parse_args(["--seed", X | T], Acc) -> parse_args(T, maps:put(seed, list_to_integer(X), Acc));
parse_args(["--maxw", X | T], Acc) -> parse_args(T, maps:put(maxw, list_to_integer(X), Acc));
parse_args([_ | T], Acc) -> parse_args(T, Acc).

idx(R, C, Cols) -> R * Cols + C.

make_grid(Rows, Cols, MaxW) ->
    N = Rows * Cols,
    Adj0 = array:new(N, [{default, []}]),
    AddUndir = fun(U, V, W, A) ->
        L1 = array:get(U, A),
        L2 = array:get(V, A),
        A1 = array:set(U, [{V, W} | L1], A),
        array:set(V, [{U, W} | L2], A1)
    end,
    AdjF = lists:foldl(
        fun(R, Acc) ->
            lists:foldl(
                fun(C, A2) ->
                    U = idx(R, C, Cols),
                    A3 =
                        case R + 1 < Rows of
                            true ->
                                V = idx(R + 1, C, Cols),
                                W = rand:uniform(MaxW),
                                AddUndir(U, V, W, A2);
                            false ->
                                A2
                        end,
                    case C + 1 < Cols of
                        true ->
                            V2 = idx(R, C + 1, Cols),
                            W2 = rand:uniform(MaxW),
                            AddUndir(U, V2, W2, A3);
                        false ->
                            A3
                    end
                end,
                Acc,
                lists:seq(0, Cols - 1)
            )
        end,
        Adj0,
        lists:seq(0, Rows - 1)
    ),
    {N, AdjF}.

make_er(N, P, MaxW) ->
    Adj0 = array:new(N, [{default, []}]),
    AddUndir = fun(U, V, W, A) ->
        L1 = array:get(U, A),
        L2 = array:get(V, A),
        A1 = array:set(U, [{V, W} | L1], A),
        array:set(V, [{U, W} | L2], A1)
    end,
    AdjF = lists:foldl(
        fun(U, A) ->
            lists:foldl(
                fun(V, A2) ->
                    case rand:uniform() < P of
                        true ->
                            W = rand:uniform(MaxW),
                            AddUndir(U, V, W, A2);
                        false ->
                            A2
                    end
                end,
                A,
                lists:seq(U + 1, N - 1)
            )
        end,
        Adj0,
        lists:seq(0, N - 1)
    ),
    {N, AdjF}.

make_ba(N, M0, M, MaxW) ->
    Adj0 = array:new(N, [{default, []}]),
    AddUndir = fun(U, V, W, A) ->
        L1 = array:get(U, A),
        L2 = array:get(V, A),
        A1 = array:set(U, [{V, W} | L1], A),
        array:set(V, [{U, W} | L2], A1)
    end,
    %% initial chain for m0
    {Adj1, Deg1} = lists:foldl(
        fun(U, {A, D}) ->
            W = rand:uniform(MaxW),
            A2 = AddUndir(U, U + 1, W, A),
            D2 = D#{U => maps:get(U, D, 0) + 1, U + 1 => maps:get(U + 1, D, 0) + 1},
            {A2, D2}
        end,
        {Adj0, #{}},
        lists:seq(0, M0 - 2)
    ),
    Sum0 = lists:sum(maps:values(Deg1)),
    FoldU = fun(U, {A, D, S}) ->
        {A2, D2, S2, _} = lists:foldl(
            fun(_, {AA, DD, SS, Seen}) ->
                R =
                    rand:uniform() *
                        (if
                            SS =< 0 -> 1.0;
                            true -> SS
                        end),
                {V, _Acc} = lists:foldl(
                    fun(Vv, {CurV, Acc}) ->
                        Acc2 = Acc + maps:get(Vv, DD, 0),
                        case Acc2 >= R of
                            true -> {Vv, Acc2};
                            false -> {CurV, Acc2}
                        end
                    end,
                    {0, 0.0},
                    lists:seq(0, U - 1)
                ),
                case V =:= U orelse sets:is_element(V, Seen) of
                    true ->
                        {AA, DD, SS, Seen};
                    false ->
                        W2 = rand:uniform(MaxW),
                        AA2 = AddUndir(U, V, W2, AA),
                        DD2 = DD#{U => maps:get(U, DD, 0) + 1, V => maps:get(V, DD, 0) + 1},
                        {AA2, DD2, SS + 2, sets:add_element(V, Seen)}
                end
            end,
            {A, D, S, sets:new()},
            lists:seq(1, M)
        ),
        {A2, D2, S2}
    end,
    {AdjF, _DegF, _SumF} = lists:foldl(FoldU, {Adj1, Deg1, Sum0}, lists:seq(M0, N - 1)),
    {N, AdjF}.

pick_sources(N, K) -> pick_sources(N, K, #{}, []).
pick_sources(_N, 0, _S, Acc) ->
    lists:reverse(Acc);
pick_sources(N, K, S, Acc) ->
    S0 = rand:uniform(N) - 1,
    case maps:is_key(S0, S) of
        true -> pick_sources(N, K, S, Acc);
        false -> pick_sources(N, K - 1, S#{S0 => true}, [{S0, 0} | Acc])
    end.

bmssp({N, Adj}, Sources, B) ->
    Dist0 = array:new(N, [{default, infinity}]),
    Heap0 = gb_sets:empty(),
    {Dist1, Heap1} = lists:foldl(
        fun({S, D0}, {Di, He}) ->
            case D0 < B of
                true -> {array:set(S, D0, Di), gb_sets:add({D0, S}, He)};
                false -> {Di, He}
            end
        end,
        {Dist0, Heap0},
        Sources
    ),
    loop(Dist1, Heap1, 0, 0, 0, infinity, Adj, B).

loop(Dist, Heap, Explored, Scanned, Pushes, Bp, Adj, B) ->
    case gb_sets:is_empty(Heap) of
        true ->
            {Dist, Explored, Scanned, Pushes, Bp};
        false ->
            {{D, V}, Heap2} = gb_sets:take_smallest(Heap),
            Cur = array:get(V, Dist),
            case Cur =/= D of
                true ->
                    loop(Dist, Heap2, Explored, Scanned, Pushes, Bp, Adj, B);
                false ->
                    case D >= B of
                        true ->
                            {Dist, Explored, Scanned, Pushes, erlang:min(Bp, D)};
                        false ->
                            L = array:get(V, Adj),
                            {Di3, He3, Sc3, Pu3, Bp3} = lists:foldl(
                                fun({To, W}, {Di, He, Sc, Pu, Bpp}) ->
                                    Sc2 = Sc + 1,
                                    Nd = D + W,
                                    CurTo = array:get(To, Di),
                                    case
                                        (Nd < B) andalso ((CurTo == infinity) orelse (Nd < CurTo))
                                    of
                                        true ->
                                            {
                                                array:set(To, Nd, Di),
                                                gb_sets:add({Nd, To}, He),
                                                Sc2,
                                                Pu + 1,
                                                Bpp
                                            };
                                        false ->
                                            case
                                                (Nd >= B) andalso (Bpp == infinity orelse Nd < Bpp)
                                            of
                                                true -> {Di, He, Sc2, Pu, Nd};
                                                false -> {Di, He, Sc2, Pu, Bpp}
                                            end
                                    end
                                end,
                                {Dist, Heap2, Scanned, Pushes, Bp},
                                L
                            ),
                            loop(Di3, He3, Explored + 1, Sc3, Pu3, Bp3, Adj, B)
                    end
            end
    end.

mem_bytes(N, M) -> M * 16 + N * 16.

key_to_string(K) when is_atom(K) -> atom_to_list(K);
key_to_string(K) when is_list(K) -> K;
key_to_string(K) when is_binary(K) -> binary_to_list(K).

json_line(Props) ->
    Parts = [
        case V of
            V when is_integer(V); is_float(V) -> io_lib:format("\"~s\":~p", [key_to_string(K), V]);
            V when is_binary(V) -> io_lib:format("\"~s\":\"~s\"", [key_to_string(K), V])
        end
     || {K, V} <- Props
    ],
    Line = lists:flatten(["{", lists:join(",", Parts), "}\n"]),
    io:put_chars(Line).

main(Args) ->
    Opts = parse_args(Args),
    Trials = maps:get(trials, Opts, 1),
    Seed = maps:get(seed, Opts, 1),
    Maxw = maps:get(maxw, Opts, 100),
    K = maps:get(k, Opts, 1),
    B = maps:get(bound, Opts, 0),
    rand:seed(exsplus, {Seed, Seed + 1, Seed + 2}),
    lists:foreach(
        fun(T) ->
            {N, Adj} =
                case maps:get(graph, Opts, grid) of
                    grid ->
                        make_grid(maps:get(rows, Opts, 1), maps:get(cols, Opts, 1), Maxw);
                    er ->
                        make_er(maps:get(n, Opts, 1), maps:get(p, Opts, 0.0), Maxw);
                    ba ->
                        make_ba(
                            maps:get(n, Opts, 1), maps:get(m0, Opts, 5), maps:get(m, Opts, 5), Maxw
                        );
                    _ ->
                        halt(0)
                end,
            Sources = pick_sources(N, K),
            T0 = erlang:system_time(nanosecond),
            {_, Expl, Sc, Pu, Bp} = bmssp({N, Adj}, Sources, B),
            T1 = erlang:system_time(nanosecond),
            M = lists:sum([length(L) || L <- [array:get(I, Adj) || I <- lists:seq(0, N - 1)]]),
            Line = [
                {impl, <<"erlang-bmssp">>},
                {lang, <<"Erlang">>},
                {graph, list_to_binary(atom_to_list(maps:get(graph, Opts)))},
                {n, N},
                {m, M},
                {k, K},
                {'B', B},
                {seed, Seed + T},
                {time_ns, T1 - T0},
                {popped, Expl},
                {edges_scanned, Sc},
                {heap_pushes, Pu},
                {'B_prime',
                    (case Bp of
                        infinity -> B;
                        _ -> Bp
                    end)},
                {mem_bytes, mem_bytes(N, M)}
            ],
            json_line(Line)
        end,
        lists:seq(0, Trials - 1)
    ),
    ok.

main() ->
    %% Entry point when invoked via: erl -s bmssp main -- ... -s init stop
    Args = init:get_plain_arguments(),
    main(Args).
