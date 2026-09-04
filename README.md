# sun_serve

A high-performance, memory-safe HTTP/1.1 server written in
[Sun](https://namo-robotics.github.io/sun/), with TLS through the Sun TLS
bundle's OpenSSL.

- One epoll event loop per worker thread, one `SO_REUSEPORT` listener per
  worker, nonblocking sockets, nonblocking TLS handshakes. No locks on the
  request path.
- HTTP/1.1 with keep-alive, pipelining, `Content-Length` and chunked request
  bodies, chunked responses, `Expect: 100-continue`, HEAD, and streamed
  file bodies.
- Strict parsing: header and body size limits, per-state timeouts, request
  smuggling defenses (`Transfer-Encoding` with `Content-Length` is refused).
- A static file handler with ETag/Last-Modified validators, index files,
  directory redirects, MIME types, and path traversal protection.
- TLS 1.2+, ALPN (`http/1.1`; the seam for `h2` is in place), certificate
  and key from PEM files.
- Every descriptor, TLS session, and buffer is owned by a class with a
  `deinit`; `unsafe` is confined to the FFI wrappers, buffers, and the parser.

## Install and try it

The rolling `dev` release provides a statically linked Linux x86-64 binary:

```sh
curl -fsSL https://github.com/namo-robotics/sun_serve/releases/download/dev/sun_serve-dev-linux-x86_64.tar.gz \
  | tar -xz
sudo install sun_serve-dev-linux-x86_64/sun_serve /usr/local/bin/sun_serve
```

Serve a directory and make a request:

```sh
mkdir -p www && printf 'hello\n' > www/index.html
sun_serve --root ./www --listen 127.0.0.1:8080
curl http://127.0.0.1:8080/
```

## Build and run

Requires the `sun` toolchain (see the `Dockerfile` for the exact image).

```
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

Handlers implement one method and run on the worker thread that owns them.
A server takes one handler per worker, so per-handler state needs no
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

`examples/hello_handler.sun` is the complete version, built by
`sun -c sun-config.json` into `build/hello_handler`; run it and open
`http://localhost:8080/hi?name=you`. The devcontainer uses host networking,
so ports bound inside it are reachable from the host as is. For richer handlers
implement `IHandler` directly (see `StaticFiles` in `src/static_files.sun`).

Request accessors (`path()`, `query_param()`, `header()`, `body_ptr()`, ...)
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
                http/ (parser, request, response, dates, MIME), tls/ (server
                OpenSSL bindings, context, session), connection (state
                machine), worker (event loop), server, static_files
cmd/sun_serve/  the command
tests/          unit and loopback integration tests, incl. HTTPS
examples/       hello_handler.sun
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
close`, `Expect`, idle timeout, graceful stop, static files), and the HTTPS tests,
which mint a certificate with the `openssl` tool and use it as the client so
they run in parallel with the rest. The VS Code test explorer runs the same
suites through `sun-config.json`.

## Status and roadmap

- Linux x86_64. The installed Sun stdlib and TLS moons are x86_64-only, so
  the aarch64 cross build in the Dockerfile waits on per-target moons.
- Not yet: `Range` requests, `sendfile`, directory listings, HTTP/2.
- `SUN_FEEDBACK.md` lists the compiler and stdlib issues found while
  building this, with reproductions.
