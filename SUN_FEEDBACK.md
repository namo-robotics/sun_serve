# Sun compiler and stdlib feedback from building sun_serve

Each section below was filed as a GitHub issue on `namo-robotics/sun`; the
link under each heading points at it. Repro snippets are complete programs
unless noted. Only the issues still open as of `sun 0.dev (7b4ceb0f6b18)`
(2026-09-18) are listed; the resolved ones (#208 through #219, #221, #223,
and #227 through #230) were removed once sun_serve dropped its workarounds
for them.


---

## Feature: `throws` on interface methods and function-pointer widening

Filed as [namo-robotics/sun#220](https://github.com/namo-robotics/sun/issues/220).

**Labels:** enhancement, semantic-analysis

- `interface I { method f() void throws IError; }` is a parse error
  (`Expected '{' or ';' after method signature in interface`), so an
  interface cannot describe a fallible operation.
- A `function (i32) i32` value is rejected where
  `function (i32) i32 throws IError` is expected
  (`No matching constructor ... candidate: init(function (i32) i32 throws IError)`).
  A non-throwing function is trivially a throwing one; the conversion should
  be implicit.

---

## Feature: block bodies in `match` arms

Filed as [namo-robotics/sun#222](https://github.com/namo-robotics/sun/issues/222).

**Labels:** enhancement, parser

Arms may now take `{ ... }` bodies, separated by commas, when the match is
used as a statement or when every block arm diverges (`return`, `continue`):

```sun
match config.tls {
  Option.Some(spec) => { load(spec); loaded = true; },
  Option.None => {}
};
```

What is still missing is a block that yields a value, so a match whose
result is used cannot mix a computed arm with one that needs several
statements; such arms are still factored into helpers.

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
