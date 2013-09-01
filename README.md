JSON-RPC 2.0 for Erlang
=======================

This is a JSON-RPC 2.0 request handler.

Features
--------

* allows any JSON encoder and decoder, as long as it supports the eep0018 style
  terms format,
* dispatches parsed requests to a simple callback function
* supports optional callback map function for batch requests, e.g. to support
  concurrent processing of the requests in a batch,
* handles rpc calls and notifications,
* supports named and unnamed parameters,
* includes unit tests for all examples in the JSON-RPC 2.0 specification.

Usage
-----

`jsonrpc2:handle/2,3` delegates the actual remote procedure call to a callback
"handler" function by passing the method name and the params. The return value
of the handler function, which should be in a form that can be encoded as JSON,
is used as the result and packed into a JSON-RPC response.

To produce an error response, the handler function is allowed to throw certain
exceptions. See *Error handling* below.

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

Since JSON parsing is not handled by this module, `jsonrpc2:parseerror()` can
be called to create a "Parse error" (-32700) response.

Invalid JSON-RPC requests (though valid JSON) are handled and reported as
Invalid Request" (-32600).

Other error responses are created by throwing in the handler function.  These
are caught and transformed into JSON-RPC error responses.

```erlang
my_handler(<<"Foo">>, [X, Y]) when is_integer(X), is_integer(Y) ->
    {[{<<"Foo says">>}, X + Y + 42}]};
my_handler(<<"Foo">>, _SomeOtherParams) ->
    throw(invalid_params);
my_handler(_SomeOtherMethod, _) ->
    throw(method_not_found).
```

The exceptions that can be used to produce JSON-RPC error responses are:

  * `throw:method_not_found` is reported as "Method not found" (-32601)
  * `throw:invalid_params` is reported as "Invalid params" (-32602),
  * `throw:internal_error` is reported as "Internal error" (-32603),
  * `throw:server_error` is reported as "Server error" (-32000),

If you also want to include `data` in the JSON-RPC error response, throw a pair
with the error type and the data, such as `{internal_error, Data}`.

For *server errors*, it is also possible to set a custom error code by throwing
a triple: `{server_error, Data, Code}`. The Code must be in the range from
-32000 to -32099.

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

