%% Copyright 2013-2014 Viktor Söderqvist
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% @doc JSON-RPC 2.0 client
-module(jsonrpc2_client).

-export_type([request/0, response/0]).
-export([create_request/1, parse_response/1, batch_call/5]).

-type call_req() :: {jsonrpc2:method(), jsonrpc2:params(), jsonrpc2:id()}.
-type notification_req() :: {jsonrpc2:method(), jsonrpc2:params()}.
-type batch_req() :: [call_req() | notification_req()].
-type request() :: call_req() | notification_req() | batch_req().

-type response() :: {ok, jsonrpc2:json()} | {error, jsonrpc2:error()}.

-type transportfun() :: fun ((binary()) -> binary()).
-type json_encode() :: fun ((jsonrpc2:json()) -> binary()).
-type json_decode() :: fun ((binary()) -> jsonrpc2:json()).

%% @doc Creates a call, notification or batch request, depending on the parameter.
-spec create_request(request()) -> jsonrpc2:json().
create_request({Method, Params}) ->
	{[{<<"jsonrpc">>, <<"2.0">>},
	  {<<"method">>, Method},
	  {<<"params">>, Params}]};
create_request({Method, Params, Id}) ->
	{[{<<"jsonrpc">>, <<"2.0">>},
	  {<<"method">>, Method},
	  {<<"params">>, Params},
	  {<<"id">>, Id}]};
create_request(Reqs) when is_list(Reqs) ->
	lists:map(fun create_request/1, Reqs).

%% @doc Parses a structured response (already json-decoded) and returns a list of pairs, with id
%% and a tuple {ok, Reply} or {error, Error}.
%% TODO: Define the structure of Error.
-spec parse_response(jsonrpc2:json()) -> [{jsonrpc2:id(), response()}].
parse_response({_} = Response) ->
	[parse_single_response(Response)];
parse_response(BatchResponse) when is_list(BatchResponse) ->
	lists:map(fun parse_single_response/1, BatchResponse).

%% @doc Calls multiple methods as a batch call and returns the results in the same order.
%% TODO: Sort out what this function returns in the different error cases.
-spec batch_call([{jsonrpc2:method(), jsonrpc2:params()}], transportfun(),
                 json_decode(), json_encode(), FirstId :: integer()) ->
	[response()].
batch_call(MethodsAndParams, TransportFun, JsonDecode, JsonEncode, FirstId) ->
	MethodParamsIds = enumerate_call_tuples(MethodsAndParams, FirstId),
	JsonReq = create_request(MethodParamsIds),
	BinReq = JsonEncode(JsonReq),
	try
		%% The transport fun can fail gracefully by throwing {transport_error, binary()}
		BinResp = try TransportFun(BinReq)
		catch throw:{transport_error, TransportError} when is_binary(TransportError) ->
			throw({jsonrpc2_client, TransportError})
		end,

		%% JsonDecode can fail (any kind of error)
		JsonResp = try JsonDecode(BinResp)
		catch _:_ -> throw({jsonrpc2_client, invalid_json})
		end,

		%% parse_response can fail by throwing invalid_jsonrpc_response
		RepliesById = try parse_response(JsonResp)
		catch throw:invalid_jsonrpc_response ->
			throw({jsonrpc2_client, invalid_jsonrpc_response})
		end,

		%% Decompose the replies into a list in the same order as MethodsAndParams.
		LastId = FirstId + length(MethodsAndParams) - 1,
		denumerate_replies(RepliesById, FirstId, LastId)

	catch throw:{jsonrpc2_client, ErrorData} ->
		%% Failure in transport function. Repeat the error data for each request to
		%% simulate a batch response.
		lists:duplicate(length(MethodsAndParams), {error, {server_error, ErrorData}})
	end.

%%----------
%% Internal
%%----------

%% @doc Helper for parse_response/1. Returns a single pair {Id, Response}.
-spec parse_single_response(jsonrpc2:json()) -> {jsonrpc2:id(), response()}.
parse_single_response({Response}) ->
	<<"2.0">> == proplists:get_value(<<"jsonrpc">>, Response)
		orelse throw(invalid_jsonrpc_response),
	Id      = proplists:get_value(<<"id">>, Response),
	is_number(Id) orelse Id == null
		orelse throw(invalid_jsonrpc_response),
	Result  = proplists:get_value(<<"result">>, Response, undefined),
	Error   = proplists:get_value(<<"error">>, Response, undefined),
	Reply = case {Result, Error} of
		{undefined, undefined} ->
			{error, {server_error, <<"Invalid JSON-RPC 2.0 response">>}};
		{_, undefined} ->
			{ok, Result};
		{undefined, {ErrorProplist}} ->
			Code = proplists:get_value(<<"code">>, ErrorProplist, -32000),
			Message = proplists:get_value(<<"message">>, ErrorProplist, <<"Unknown error">>),
			ErrorTuple = case proplists:get_value(<<"data">>, ErrorProplist) of
			    undefined ->
					{jsonrpc2, Code, Message};
			    Data ->
					{jsonrpc2, Code, Message, Data}
			end,
			{error, ErrorTuple};
		_ ->
			%% both error and result
			{error, {server_error, <<"Invalid JSON-RPC 2.0 response">>}}
	end,
	{Id, Reply}.

%% @doc Gives each method-params pair a number. Returns a list of triples: method-params-id.
enumerate_call_tuples(MethodParamsPairs, FirstId) ->
	enumerate_call_tuples(MethodParamsPairs, FirstId, []).

%% @doc Helper for enumerate_call_tuples/2.
enumerate_call_tuples([{Method, Params} | MPs], NextId, Acc) ->
	Triple = {Method, Params, NextId},
	enumerate_call_tuples(MPs, NextId + 1, [Triple | Acc]);
enumerate_call_tuples([], _, Acc) ->
	lists:reverse(Acc).

%% @doc Finds each pair {Id, Reply} for each Id in the range FirstId..LastId in the proplist
%% Replies. Removes the id and returns the only the replies in the correct order.
denumerate_replies(Replies, FirstId, LastId) ->
	denumerate_replies(dict:from_list(Replies), FirstId, LastId, []).

%% @doc Helper for denumerate_replies/3.
denumerate_replies(ReplyDict, FirstId, LastId, Acc) when FirstId =< LastId ->
	Reply = dict:fetch(FirstId, ReplyDict),
	Acc1 = [Reply | Acc],
	denumerate_replies(ReplyDict, FirstId + 1, LastId, Acc1);
denumerate_replies(_, _, _, Acc) ->
	lists:reverse(Acc).

%%------------
%% Unit tests
%%------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

enumerate_call_tuples_test() ->
	Input  = [{x, foo}, {y, bar}, {z, baz}],
	FirstId = 3,
	Expect = [{x, foo, 3}, {y, bar, 4}, {z, baz, 5}],
	Expect = enumerate_call_tuples(Input, FirstId).

denumerate_replies_test() ->
	Input = [{3, foo}, {5, baz}, {4, bar}],
	FirstId = 3,
	LastId = 5 = FirstId + length(Input) - 1,
	Expect = [foo, bar, baz],
	Expect = denumerate_replies(Input, FirstId, LastId).

transport_error_test() ->
	TransportFun = fun (_) -> throw({transport_error, <<"404 or whatever">>}) end,
	JsonEncode = fun (_) -> <<"foo">> end,
	JsonDecode = fun (_) -> [] end,
	MethodsAndParams = [{<<"foo">>, []}],
	Expect = [{error, {server_error, <<"404 or whatever">>}}],
	?assertEqual(Expect, batch_call(MethodsAndParams, TransportFun, JsonDecode, JsonEncode, 1)).

transport_return_invalid_json_test() ->
	TransportFun = fun (_) -> <<"some non-JSON junk">> end,
	JsonEncode = fun (_) -> <<"{\"foo\":\"bar\"}">> end,
	JsonDecode = fun (_) -> throw(invalid_json) end,
	MethodsAndParams = [{<<"foo">>, []}],
	Expect = [{error, {server_error, invalid_json}}],
	?assertEqual(Expect, batch_call(MethodsAndParams, TransportFun, JsonDecode, JsonEncode, 1)).

-endif.
