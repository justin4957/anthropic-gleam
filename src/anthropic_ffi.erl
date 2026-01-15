-module(anthropic_ffi).
-export([is_nil/1, json_string_to_gleam_json/1]).

%% Check if a value is the nil atom (used for JSON null)
is_nil(nil) -> true;
is_nil(null) -> true;
is_nil(_) -> false.

%% Convert a JSON string to Gleam's internal Json representation
%% This parses the JSON string and converts Erlang terms to the format
%% expected by gleam_json
json_string_to_gleam_json(JsonString) ->
    case json:decode(JsonString) of
        Term -> erlang_term_to_gleam_json(Term)
    end.

%% Convert an Erlang term (from json:decode) to Gleam Json representation
%% The gleam_json library uses specific representations for each type
erlang_term_to_gleam_json(Term) when is_map(Term) ->
    Entries = maps:fold(fun(K, V, Acc) ->
        [{K, erlang_term_to_gleam_json(V)} | Acc]
    end, [], Term),
    gleam_json_ffi:object(Entries);
erlang_term_to_gleam_json(Term) when is_binary(Term) ->
    gleam_json_ffi:string(Term);
erlang_term_to_gleam_json(Term) when is_integer(Term) ->
    gleam_json_ffi:int(Term);
erlang_term_to_gleam_json(Term) when is_float(Term) ->
    gleam_json_ffi:float(Term);
erlang_term_to_gleam_json(true) ->
    gleam_json_ffi:bool(true);
erlang_term_to_gleam_json(false) ->
    gleam_json_ffi:bool(false);
erlang_term_to_gleam_json(null) ->
    gleam_json_ffi:null();
erlang_term_to_gleam_json(nil) ->
    gleam_json_ffi:null();
erlang_term_to_gleam_json(Term) when is_list(Term) ->
    Items = [erlang_term_to_gleam_json(I) || I <- Term],
    gleam_json_ffi:array(Items);
erlang_term_to_gleam_json(_) ->
    gleam_json_ffi:null().
