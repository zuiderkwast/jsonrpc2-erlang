JSON-RPC 2.0 for Erlang
=======================

This is a JSON-RPC 2.0 request handler. It does not handle JSON decoding and
encoding. This means the JSON decoding and encoding must be handled by the
caller. It also means that you may use the JSON library of your choice.

Features
--------

* allows any JSON encoder and decoder, as long as it supports the eep0018 style
  terms format,
* no dependencies, except OTP,
* dispatches parsed requests to a simple callback function
* supports optional callback map function for batch requests, e.g. to support
  concurrent processing of the requests in a batch,
* handles rpc calls and notifications,
* supports named and unnamed parameters,
* includes unit tests for all examples in the JSON-RPC 2.0 specification.

Usage
-----

The processing is done using a callback function. The method and params are passed to the callback
function and the return value are used as results. Any exception from the callback function is
caught and results in an appropriate error message.

Example
-------

``` erlang

my_handler(Method, Params) ->
    io:format("Got JSON-RPC call to ~p with params ~p~n", [Method, Params]),
    case Method of
        <<"foo">> -> lists:reverse(Params);
        <<"bar">> -> lists:max(Params) + 42
    end.

example() ->
    BinJson = <<"{\"jsonroc\": \"2.0\", \"method\": \"foo\", \"params\": [1,2,3], \"id\": 1}">>,

    Response = try jiffy:decode(BinJson) of
                   DecodedJson ->
                       jsonrpc2:handle(DecodedJson, fun my_handler/2)
               catch
                   _:_ ->
                       jsonrpc2:parseerror()
               end,

    case Response of
        {reply, Reply} ->
            io:format("Reply ~p~n", [jiffy:encode(Reply)]);
        noreply ->
            io:format("No reply~n")
    end.
```

Concurrent Batch Requests
-------------------------

Using jsonrpc2:handle/2, the requests in a batch request are processesed
sequentially. To allow concurrent processing, you may use jsonrpc2:handle/3,
where the 3rd argument should be a function compatible with lists:map/2, such
as the plists:map/2. You may also want to implement you own map function, to
use something like a pool of workers.

Error Handling
--------------

* For JSON parsing errors, which is not handled by this module,
  jsonrpc2:parseerror() can be called to create a "Parse error" (-32700)
  response.
* Invalid JSON-RPC requests (though valid JSON) are handled and reported as
  "Invalid Request" (-32600).
* Any exceptions and errors occuring in the handler callback function are
  caught and reported in the following way:
  * error:undef  is reported as "Method not found" (-32601),
  * error:badarg and error:function_clause are reported as "Invalid params"
    (-32602),
  * any other error or exception is reported as "Internal error" (-32603).

The error undef normally occur in Erlang when an undefined function is called.
A function_clause or badarg occurs when a function is not defined for a
specific set of parametes or otherwise doesn't accept the parameters,
respectively. You can either let them occur naturally in your handler or
trigger them manually using erlang:error/1.

JSON Data Format
----------------

    Erlang                          JSON            Erlang
    ==========================================================================

    null                       -> null           -> null
    true                       -> true           -> true
    false                      -> false          -> false
    "hi"                       -> [104, 105]     -> [104, 105]
    <<"hi">>                   -> "hi"           -> <<"hi">>
    hi                         -> "hi"           -> <<"hi">>
    1                          -> 1              -> 1
    1.25                       -> 1.25           -> 1.25
    []                         -> []             -> []
    [true, 1.0]                -> [true, 1.0]    -> [true, 1.0]
    {[]}                       -> {}             -> {[]}
    {[{foo, bar}]}             -> {"foo": "bar"} -> {[{<<"foo">>, <<"bar">>}]}
    {[{<<"foo">>, <<"bar">>}]} -> {"foo": "bar"} -> {[{<<"foo">>, <<"bar">>}]}

Compatible JSON parsers
-----------------------
* Jiffy, https://github.com/davisp/jiffy
* erlang-json, https://github.com/hio/erlang-json
* Mochijson2 using ```mochijson2:decode(Bin, [{format, eep18}])```

Links
-----
* ejrpc2, another JSON-RPC 2 library, https://github.com/jvliwanag/ejrpc2
* The JSON-RPC 2.0 specification, http://www.jsonrpc.org/specification

