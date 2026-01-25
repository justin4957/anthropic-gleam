-module(anthropic_testing_ffi).
-export([unique_integer/0]).

unique_integer() ->
    erlang:unique_integer([positive]).
