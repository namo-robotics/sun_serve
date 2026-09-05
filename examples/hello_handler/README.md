# hello_handler

A small program built on the sun_serve library. Where the `sun_serve` binary
only serves files, this one answers requests itself with a handler class:

| Route | What it does |
|---|---|
| `GET /hi?name=NAME` | greets `NAME`, or `world` without a name |
| `POST /echo` | sends the request body back; other methods get 405 |
| `GET /stats` | how many requests the worker that answered has handled |
| `WS /ws` | echoes complete text and binary WebSocket messages |
| anything else | 404 |

`WebSocketHandle` clones can queue bounded asynchronous sends from other threads. The server negotiates `permessage-deflate` by default without client or server context takeover.

The handler keeps its request counter as a plain field. Each worker thread
owns its own handler instance, so per-handler state needs no locking.

## Build, run, test

From the repository root, with the `sun` toolchain installed:

```sh
sun -c sun-config.json        # builds build/hello_handler and build/hello_handler_test
build/hello_handler &
curl 'http://127.0.0.1:8080/hi?name=sun'
curl -d 'ping' http://127.0.0.1:8080/echo
curl http://127.0.0.1:8080/stats
websocat ws://127.0.0.1:8080/ws
```

```sh
build/hello_handler_test                   # compiled tests
sun test examples/hello_handler/main.sun   # or under the JIT, no build step
```

`scripts/test.sh` runs these tests alongside the library's, and CI runs them
on every push.

## Files

- `main.sun` holds the handler, the `main` that starts a `Server` with one
  handler per CPU, and the manifest that links `sun_serve.moon`.
- `hello_tests.sun` starts a real server on a loopback port for each test,
  sends one request over a TCP socket, and checks the reply. The same pattern
  works for testing any handler built on sun_serve.
