

<div align="center">

# Sun Serve

[![ci](https://github.com/namo-robotics/sun_serve/actions/workflows/ci.yml/badge.svg)](https://github.com/namo-robotics/sun_serve/actions/workflows/ci.yml) [![release-dev](https://github.com/namo-robotics/sun_serve/actions/workflows/release-dev.yml/badge.svg)](https://github.com/namo-robotics/sun_serve/actions/workflows/release-dev.yml)

### A high-performance and memory-safe web server written in
[Sun](https://namo-robotics.github.io/sun/)


Supports **x86_64 Linux** only

</div>

## Key Features

- ⚡ **Fast.** An epoll loop per worker thread and no locks on the request path:
  ~67k requests/s on loopback, ~1.6 GB/s on large files.
- 📁 **Static files, done properly.** ETag and `Last-Modified` revalidation, index
  files, directory redirects, MIME types, `Cache-Control`, and traversal
  protection.
- 🔒 **HTTPS included.** TLS 1.2+ with certificate and key from PEM files.
- 🌐 **HTTP/1.1 and HTTP/2.** ALPN and h2c negotiation, HPACK, multiplexed streams, flow control, and HTTP/1.1 fallback.
- 🔌 **WebSockets.** RFC 6455 Upgrade and RFC 8441 extended CONNECT with `permessage-deflate`, message callbacks, and asynchronous send handles.
- 🛡️ **Hard to knock over.** Header and body size limits, per-state timeouts,
  request smuggling refused, and graceful shutdown on `SIGINT`/`SIGTERM`.
- 📦 **A binary or a library.** Serve a directory with one static binary and no
  dependencies, or link the library and write your own handler.

## Install and try it

The rolling `dev` release provides a statically linked Linux x86-64 binary:

```sh
curl -fsSL https://github.com/namo-robotics/sun_serve/releases/download/dev/sun_serve-dev-linux-x86_64.tar.gz \
  | tar -xz
sudo install sun_serve-dev-linux-x86_64/sun_serve /usr/local/bin/sun_serve
```

There are two ways to use sun_serve: run the binary as a static file server,
or build your own program on the library and give it a handler.

**Static serving** needs nothing but the binary and a directory:

```sh
mkdir -p www && printf 'hello\n' > www/index.html
sun_serve --root ./www --listen 127.0.0.1:8080 &
curl http://127.0.0.1:8080/
```

**A custom handler** is a program that links the library and answers requests
itself. [examples/hello_handler](examples/hello_handler) is a complete one,
with tests; building it needs the `sun` toolchain (see
[Build and run](#build-and-run)):

```sh
sun -c sun-config.json           # produces build/hello_handler
build/hello_handler &
curl 'http://127.0.0.1:8080/hi?name=you'
```

The two compose: a custom handler can fall back to the same `StaticFiles`
handler the binary uses. [Using the library](#using-the-library) shows the code.

## Build and run

Requires the `sun` toolchain (see the `Dockerfile` for the exact image).

```bash
scripts/build.sh          # format check + sun -c sun-config.json -> build/
scripts/test.sh           # compiled test suites (add --jit to run under the JIT)
scripts/mkcert.sh build   # self-signed localhost certificate for local use
build/sun_serve --root ./www --listen 0.0.0.0:8080 \
    --tls-listen 0.0.0.0:8443 --cert build/cert.pem --key build/key.pem
```

`build/sun_serve --help` lists every flag: listeners, worker count, log
level, body and header limits, keep-alive timeout, index file, and
`Cache-Control`. Access log lines go to stdout, diagnostics to stderr.
`SIGINT`/`SIGTERM` stop accepting, let in-flight requests finish, and exit 0.

## Using the library

Handlers implement the unified HTTP and WebSocket interface and run on the worker thread that owns them.
A server takes one unified HTTP and WebSocket handler per worker, so per-handler state needs no
synchronization:

```sun
using std;
using sun_serve;

function hello(req: const ref Request, resp: ref Response) void {
  resp.set_content_type("text/plain");
  resp.set_body("hello\n");
}

function main() i32 throws IError {
  var alloc = make_heap_allocator();
  var cfg = Config(alloc);
  cfg.add_listen(ipv4_any(), 8080);
  install_signal_handlers();
  var server = Server(alloc, cfg, fn_handlers(alloc, hello, online_cpus()));
  return server.run();
}
```

For richer handlers implement [`IHandler`](src/handler.sun) directly, which
is what [`StaticFiles`](src/static_files.sun) does; a handler can also hold a
`StaticFiles` and delegate to it for the paths it does not serve itself.
[examples/hello_handler](examples/hello_handler) is a complete program built
this way: a handler class with per-worker state, query parameters, request
bodies, and end-to-end tests that CI runs. The devcontainer uses host
networking, so ports bound inside it are reachable from the host as is.

WebSocket upgrades use `handle_websocket`; open, message, close, and error callbacks run on the owning worker. Cloneable `WebSocketHandle` values support bounded sends from other threads and wake the owning worker immediately. `permessage-deflate` is enabled by default with client and server context takeover disabled; set `Config.websocket_compression` to `false` or pass `--no-websocket-compression` to opt out. The hello example exposes an echo endpoint at `/ws`.

Request accessors (`path()`, `query_param()`, `header()`, `body_buffer()`, ...)
are views into the connection's buffer and are valid only during `handle()`;
the `String`-returning variants copy. Responses take a status, headers, an
in-memory body, a file to stream (`send_file`), or chunks (`write_chunk`).

The library is compiled from source through the `$SUN_SERVE_SRC` path
variable in `sun-config.json`. `build/sun_serve.moon` is also produced, but
consuming it from another program currently trips two compiler issues
(see `SUN_FEEDBACK.md`), so the source route is the supported one for now.

## Layout

```
src/            the library: sys_ffi (libc boundary), epoll, net, buffer,
                http/ (parser, request, response, dates, MIME), HTTP/2, HPACK, WebSocket, tls/ (server
                OpenSSL bindings, context, session), connection (state
                machine), worker (event loop), server, static_files
cmd/sun_serve/  the command
tests/          unit and loopback integration tests, incl. HTTPS
examples/       hello_handler/, a custom handler with its own tests
scripts/        build.sh, test.sh, bench.sh, mkcert.sh
```

## Configuration defaults

| Setting | Default |
|---|---|
| max request head | 16 KiB |
| max request body | 8 MiB |
| max headers | 100 |
| connections per worker | 8192 |
| handshake / header / body / write timeout | 10 s / 30 s / 60 s / 60 s |
| keep-alive idle timeout | 75 s |
| shutdown drain | 5 s |

## Throughput

Loopback on a 22-core machine with 4 workers, keep-alive connections, and a
Python asyncio client (`scripts/bench.sh` drives whichever of oha, wrk, hey,
or ab is installed):

| Request | Concurrency | Requests/s |
|---|---|---|
| 1 KiB file, HTTP | 64 | ~67,000 |
| 1 KiB file, HTTPS | 64 | ~51,000 |
| 1.4 MiB file, HTTP | 16 | ~1,170 (about 1.6 GB/s) |
| 1.4 MiB file, HTTPS | 16 | ~590 |

The small-file numbers are bounded by the Python client, not the server.

## Tests

`scripts/test.sh` runs the unit tests (buffer, epoll, parser, response,
dates, MIME, path normalization), the loopback integration tests (keep-alive,
pipelining, large bodies, chunked both ways, limits, HEAD, `Connection:
close`, `Expect`, idle timeout, graceful stop, static files), the HTTPS tests,
which mint a certificate with the `openssl` tool and use it as the client so
they run in parallel with the rest, and the example's tests. The VS Code test explorer runs the same
suites through `sun-config.json`.

## Status and roadmap

- Linux x86_64. The installed Sun stdlib and TLS moons are x86_64-only, so
  the aarch64 cross build in the Dockerfile waits on per-target moons.
- Not yet: `Range` requests, `sendfile`, and directory listings. See
  [ROADMAP.md](ROADMAP.md) for the full list, in order of importance.
- `SUN_FEEDBACK.md` lists the compiler and stdlib issues found while
  building this, with reproductions.
