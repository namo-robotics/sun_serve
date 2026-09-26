# Sun compiler and stdlib feedback from building sun_serve

Each item links to its issue on `namo-robotics/sun`.
Repro snippets are complete programs unless noted. Open issues and remaining
limitations were checked with `sun 0.dev (a69c9fb35814)`
(2026-09-25). Only unresolved feedback is listed below.

---

## Feature: `throws` on interface methods

Filed as [namo-robotics/sun#220](https://github.com/namo-robotics/sun/issues/220).

**Labels:** enhancement, semantic-analysis

`interface I { method f() void throws IError; }` is a parse error
(`Expected '{' or ';' after method signature in interface`), so an
interface cannot describe a fallible operation.

---

## Feature: value-yielding block bodies in `match` arms

Filed as [namo-robotics/sun#222](https://github.com/namo-robotics/sun/issues/222).

**Labels:** enhancement, parser

A block arm cannot yield a value, so a match whose result is used cannot
mix a computed arm with one that needs several statements; such arms are
still factored into helpers.

---

## Feature (stdlib): export the errno / nonblocking helpers

Filed as [namo-robotics/sun#224](https://github.com/namo-robotics/sun/issues/224).

**Labels:** enhancement, stdlib

`errno()`, `set_fd_nonblocking()`, and every libc extern in `sys.sun` are
private to `module std`. A server module has to redeclare `fcntl`, `close`,
`__errno_location` itself just to distinguish EAGAIN from a real error.
Suggested: make `errno()` and `set_fd_nonblocking(fd, enabled)` public, or
add a non-throwing readiness API to `TcpStream`/`TcpListener` (e.g.
`try_recv`/`try_accept` returning a count or a would-block/closed status)
instead of throwing on EAGAIN.

---

## Feature (stdlib): epoll-based readiness alongside `Poller`

Filed as [namo-robotics/sun#225](https://github.com/namo-robotics/sun/issues/225).

**Labels:** enhancement, stdlib

`std.io.Poller` wraps `poll(2)` only: O(n) per wait, `remove()` is O(n²) and
drops `revents` of shifted entries, and interest cannot be modified in place.
sun_serve had to declare `epoll_create1/ctl/wait` and `accept4` and measure
the `struct epoll_event` layout at runtime because there is no architecture
intrinsic (`_target_is` knows only the OS; the struct is packed on x86_64 and
16 bytes on aarch64). A `std.io.EventLoop` (epoll on Linux, kqueue on macOS)
with add/modify/remove and a token per descriptor would let servers stay in
safe code.

---

## Feature (tls bundle): server-side TLS

Filed as [namo-robotics/sun#226](https://github.com/namo-robotics/sun/issues/226).

**Labels:** enhancement, tls

`tls.moon` binds only `TLS_client_method`/`SSL_connect`. The bundle carries
the whole of libssl, so a server needs about twenty more externs
(`TLS_server_method`, `SSL_CTX_use_certificate_chain_file`,
`SSL_CTX_use_PrivateKey_file`, `SSL_do_handshake`, ALPN callbacks, ...) and a
nonblocking `handshake/read/write` that maps `SSL_ERROR_WANT_READ/WRITE`.
sun_serve implements this in `src/tls/`; it would fit naturally in the bundle
as `TlsListener`/`TlsServerContext`.

---

## Bug: interface constraints reject concrete handlers in nested test modules

Filed as [namo-robotics/sun#333](https://github.com/namo-robotics/sun/issues/333).

**Labels:** bug

Reproduced with `sun 0.dev (a69c9fb35814)` using `sun test`.

The concrete class implements the required interface, but using the constrained
server type as a field in a nested test module fails with
`type argument 'Concrete' does not satisfy constraint 'Handler'`.

```sun
/* Contains the handler types. */
public module sample {
  interface Handler { public method handle() void; }
  class Concrete implements Handler { public method handle() void {} }
  class Server<H: Handler> {
    var handler: H;
    init(handler: H) { this.handler = handler; }
  }
}
/* Contains a caller. */
public module sample {
  module tests {
    class Fixture {
      var server: Server<Concrete>;
      init() { this.server = Server<Concrete>(Concrete()); }
    }
    test_function build() { var fixture = Fixture(); }
  }
}
function main() i32 { return 0; }
manifest { libraries: ["stdlib.moon"] }
```

sun_serve uses concrete generic owners (`Server<H>`, `Worker<H>`, and
`WorkerArgs<H>`) without an explicit interface constraint. Calls into the
connection code still require `ref IHandler`, so handler implementations are
checked when the worker is instantiated. Owning `IHandler` values is no longer
supported by Sun.
