# Sun compiler and stdlib feedback from building sun_serve

Each section below was filed as a GitHub issue on `namo-robotics/sun`; the
link under each heading points at it. Repro snippets are complete programs
unless noted. Only the issues still open as of `sun 0.dev (e9fe7a0e0338)`
(2026-09-19) are listed; the resolved ones (#208 through #219, #221, #223,
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

---

## Regression: `continue` or `break` in a block arm of a match that yields a value

Filed as [namo-robotics/sun#309](https://github.com/namo-robotics/sun/issues/309).

**Labels:** bug, semantic-analysis

Worked at `7b4ceb0f6b18`; fails at `e9fe7a0e0338` with
`Internal error: expression type was not prepared for inference`, reported at
the `continue`. A block arm that ends in `return` still compiles.

```sun
using std;

function pick(i: i64) Option<i64> {
  if (i % 2 == 0) {
    return Option.Some(i);
  }
  return Option.None;
}

function main() i32 {
  var total: i64 = 0;
  for (var i: i64 = 0; i < 4; i = i + 1) {
    var v: i64 = match pick(i) {
      Option.Some(x) => x,
      Option.None => {
        continue;
      }
    };
    total = total + v;
  }
  println(total);
  return 0;
}

manifest {
  libraries: ["stdlib.moon"]
}
```

sun_serve's HTTP/2 frame loop used this shape to skip unknown frame types; it
now matches as a statement and handles the known frame inside the arm.

---

## Bug: string literals with `\xNN` bytes above 0x7f upset the AST serializer

Filed as [namo-robotics/sun#310](https://github.com/namo-robotics/sun/issues/310).

**Labels:** bug, moon

`StringLiteral.value` is a protobuf `string`, which must be valid UTF-8, but
`\xNN` escapes make byte strings.

- New at `e9fe7a0e0338`: any program with such a literal prints
  `[libprotobuf ERROR ...] String field 'sun.proto.ast.StringLiteral.value'
  contains invalid UTF-8 data when serializing a protocol buffer` once per
  literal, under the JIT and with `-c`. The program still runs correctly, so
  this is noise, but it reads like a build failure. sun_serve's build prints
  it for the WebSocket deflate trailer and for the HPACK bytes in its tests.
- Before and after: when the literal sits in a *generic* function of a
  library, the moon is written but cannot be read back (`invalid UTF-8 data
  when parsing`), and every symbol of the library is then unknown to the
  consumer.

```sun
// lib.sun: sun --emit-moon -o blib.moon lib.sun
public module blib {
  using std;

  public function marker_len<T>(alloc: const ref HeapAllocator, x: T) i64 {
    var s = String(alloc, "\xff\xfe");
    return s.length();
  }
}

manifest {
  libraries: ["stdlib.moon"]
}
```

```sun
// app.sun: sun --lib-path . app.sun  ->  Unknown generic function or class 'marker_len'
using std;
using blib;

function main() i32 {
  var alloc = HeapAllocator();
  println(marker_len<i32>(alloc, 1));
  return 0;
}

manifest {
  libraries: ["stdlib.moon", "blib.moon"]
}
```

Suggested: make the field `bytes`.

---

## Crash: a `const` initialized from another `const`

Filed as [namo-robotics/sun#311](https://github.com/namo-robotics/sun/issues/311).

**Labels:** bug, semantic-analysis

The compiler segfaults, with no diagnostic, at file scope and inside a
module, under the JIT and with `-c`. sun_serve spells each constant out as a
literal instead.

```sun
using std;

const A: i64 = 4;
const B: i64 = A;

function main() i32 {
  println(B);
  return 0;
}

manifest {
  libraries: ["stdlib.moon"]
}
```
