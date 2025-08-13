Erlang BMSSP CLI

- Requires: Erlang/OTP and jsx (JSON lib) available in code path (or install with rebar3)
- Build: erlc bmssp.erl
- Run: erl -noshell -pa . -s bmssp main -- --graph grid --rows 50 --cols 50 --k 4 --B 100 --trials 1 --seed 1 --maxw 100 -s init stop

# Erlang BMSSP

Compile and run:

```sh
erlc bmssp.erl
erl -noshell -pa . -s bmssp main -- --trials 1 --k 4 --B 100 --seed 42 --maxw 100 --graph er --n 100 --p 0.01 -s init stop
```
Erlang BMSSP CLI

- Requires: Erlang/OTP and jsx (JSON lib) available in code path (or install with rebar3)
- Build: erlc bmssp.erl
- Run: erl -noshell -pa . -s bmssp main -- --graph grid --rows 50 --cols 50 --k 4 --B 100 --trials 1 --seed 1 --maxw 100 -s init stop
