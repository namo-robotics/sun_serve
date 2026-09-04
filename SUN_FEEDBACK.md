# Sun compiler and stdlib feedback from building sun_serve

Each section below was filed as a GitHub issue on `namo-robotics/sun`
(issues #208 through #230); the link under each heading points at it. Everything was reproduced with `sun 0.dev (d6eccc3079ee)`
on x86_64 Linux. Repro snippets are complete programs unless noted.

---

## Bug: `create_unique<T>` / `_init<T>` do not store primitive values

Filed as [namo-robotics/sun#208](https://github.com/namo-robotics/sun/issues/208).

**Labels:** bug, codegen, stdlib

`HeapAllocator.create_unique<i32>(0)` (and `create<i32>(0)`) allocates the cell
but never writes the argument, so the cell holds whatever malloc returned.
Class types are initialized correctly; only primitives are affected.

```sun
using std;
function main() i32 {
  var alloc = make_heap_allocator();
  for (var i: i32 = 0; i < 1000; i = i + 1) {      // dirty the heap
    var p: raw_ptr<u8> = alloc.alloc_raw(4);
    unsafe { _store<i32>(p, 0, 305419896); };
    alloc.dealloc_raw(p, 4);
  }
  var bad: i32 = 0;
  for (var i: i32 = 0; i < 1000; i = i + 1) {
    var u = alloc.create_unique<i32>(0);
    if (u.get() != 0) { bad = bad + 1; }
  }
  println(bad);   // expected 0, prints 1000
  return 0;
}
manifest { libraries: ["stdlib.moon"] }
```

**Impact:** a `Unique<i32>` used as a cross-thread stop flag read garbage and
stopped workers at random. Workaround: `_atomic_store_i32(u.get_raw(), 0)`
right after creation.

---

## Bug: class values produced by `match` expressions are dropped too early

Filed as [namo-robotics/sun#209](https://github.com/namo-robotics/sun/issues/209).

**Labels:** bug, codegen, ownership, critical

Two related use-after-free / double-drop cases, both silent:

1. A class constructed inside a match arm is destroyed before the match
   result is used. The struct is copied out but its `deinit` already ran.
2. Returning a match expression directly from a function drops the payload
   once inside the function and again in the caller.

```sun
using std;
var drops: i32 = 0;
class Res {
  public var id: i32;
  init(id: i32) { this.id = id; }
  deinit() { if (this.id != 0) { drops = drops + 1; } }
}
function make(id: i32) Option<Res> { return Option.Some(Res(id)); }
function take_it(o: Option<Res>) Res {
  return match o { Option.Some(r) => r, Option.None => Res(99) };
}
function main() i32 {
  var alloc = make_heap_allocator();
  var a: String = match make(1) {            // case 1
    Option.Some(x) => String(alloc, "x"),
    Option.None => String(alloc, "fallback-temp")
  };
  println(a.length());   // 1 (struct intact)
  println(a);            // prints nothing: the buffer was freed
  if (true) {
    var r2: Res = take_it(make(2));          // case 2
    println(drops);      // 1 already: dropped inside take_it
  }
  println(drops);        // 2: dropped again by the caller
  return 0;
}
manifest { libraries: ["stdlib.moon"] }
```

Extracting a payload with `match` into a local in the same scope works
(one drop at scope end), and `Vec.take(i)` works. The two failing shapes are
the natural way to write `unwrap_or`, so this bit sun_serve repeatedly:
random 304s (a garbage `If-None-Match` string), a segfault from a
double-freed `String`, and a corrupted thread handle.

Workarounds used: build the fallback value in a local before the `match`
and name it in the arm; assign the match to a local and return the local.

---

## Bug: negative `i32` literal assigned to an existing `i64` is zero-extended

Filed as [namo-robotics/sun#210](https://github.com/namo-robotics/sun/issues/210).

**Labels:** bug, codegen

Declaration with an initializer works; plain assignment and field assignment
produce `4294967295` instead of `-1`.

```sun
using std;
class Box { var v: i64; init() { this.v = 0; } }
function main() i32 {
  var a: i64 = -1;  println(a);        // -1 (ok)
  var c: i64 = 0;   c = -1; println(c); // 4294967295 (wrong)
  var b = Box();    b.v = -1; println(b.v); // 4294967295 (wrong)
  var d: i64 = 0;   d = -1i64; println(d); // -1 (workaround)
  return 0;
}
manifest { libraries: ["stdlib.moon"] }
```

**Impact:** a "no Content-Length" sentinel became a 4 GiB length and every
request was rejected with 413. Workaround: suffix the literal (`-1i64`).

---

## Bug: `u64` literals above `i64::MAX` saturate to `9223372036854775807`

Filed as [namo-robotics/sun#211](https://github.com/namo-robotics/sun/issues/211).

**Labels:** bug, parser

```sun
using std;
function main() i32 {
  var v: u64 = 18446744073709551615u64;  println(v);  // prints 9223372036854775807
  const m: u64 = 14627333968358193854;                  // same, silently
  return 0;
}
manifest { libraries: ["stdlib.moon"] }
```

Expected: the full u64 value, or a compile error if the literal is rejected.
No diagnostic is emitted.

---

## Bug: `\xNN` string escapes are not decoded

Filed as [namo-robotics/sun#212](https://github.com/namo-robotics/sun/issues/212).

**Labels:** bug, lexer, docs

The builtin-types page lists `\xNN`, but `"\x08http/1.1".length()` is 12, not
9: the four characters `\`, `x`, `0`, `8` are kept verbatim. Needed for
binary protocol strings such as ALPN wire lists; workaround is
`s.append_char(8)` at runtime.

---

## Bug: interface constraints on generics fail inside a module

Filed as [namo-robotics/sun#213](https://github.com/namo-robotics/sun/issues/213).

**Labels:** bug, semantic-analysis, generics

The same code type-checks at file scope and fails inside `module`:

```sun
module spike {
  using std;
  public interface IHandler { public method handle(x: i32) i32; }
  public class Impl implements IHandler {
    init() {}
    public method handle(x: i32) i32 { return x + 1; }
  }
  public class Box<H: IHandler> {
    var inner: H;
    init(inner: H) { this.inner = inner; }
    public method go(x: i32) i32 { return this.inner.handle(x); }
  }
  public function run() i32 { var b = Box<Impl>(Impl()); println(b.go(41)); return 0; }
}
function main() i32 { return spike.run(); }
manifest { libraries: ["stdlib.moon"] }
```

```
Error: type argument 'Impl' does not satisfy constraint 'IHandler' on type parameter 'H' of generic class 'Box'
```

Moving the interface, class, and `Box` to file scope prints `42`. Moving only
the interface to file scope makes the constraint pass but then dynamic calls
through an `IHandler` field fail with `Unknown member 'handle' on interface
'IHandler'`. Related symptoms:

- `function call<H: IHandler>(...)` in a module must be invoked as
  `spike.call<Impl>(...)`; the unqualified form reports
  `Unknown generic function or class 'call'`.
- `class Impl implements spike.IHandler` and `Box<H: spike.IHandler>` are
  parse errors, so the constraint cannot be qualified either.

**Impact:** sun_serve had to give up static dispatch (`Server<H>`) and use
interface values.

---

## Bug: member access through a generic class field inside a generic function

Filed as [namo-robotics/sun#214](https://github.com/namo-robotics/sun/issues/214).

**Labels:** bug, semantic-analysis, generics

With a satisfied constraint, `b.inner.handle(x)` fails when `b: ref Box<H>` is
a parameter of a generic *function*, while the identical expression inside a
method of `Box<H>` compiles.

```
Error: Cannot access member 'handle' on unconstrained type parameter 'H'
```

(Same `Box`/`Impl` as the previous issue, at file scope.)

```sun
function call_boxed<H: IHandler>(b: ref Box<H>, x: i32) i32 {
  return b.inner.handle(x);   // error
}
```

---

## Feature: generic interfaces as constraints (`<H: IHandler<H>>`)

Filed as [namo-robotics/sun#215](https://github.com/namo-robotics/sun/issues/215).

**Labels:** enhancement, parser, generics

`class Server<H: IHandler<H>>` and `<H: IHandler<H> >` both fail with
`expected '>' after type parameters`; constraints accept a bare identifier
only. This blocks the `IIterable<T, Self>` pattern from being used as a
constraint, e.g. an interface with a `const method clone() Self`.

---

## Bug: interface parameters break linking across a `.moon` boundary

Filed as [namo-robotics/sun#216](https://github.com/namo-robotics/sun/issues/216).

**Labels:** bug, moon, linker

A library exports `class Runner { init(h: IHandler) ... }`. A consumer
implements `IHandler` and calls `Runner(h)`. Type-checking passes, linking
fails:

```
undefined reference to `$310415a5$_mylib_Runner_init$$310415a5$_mylib_IHandler'
```

The moon itself contains `$310415a5$_mylib_Runner_init$mylib_IHandler`
(no hash prefix on the parameter type). The mangling of interface-typed
parameters differs between the exporting and importing compilation.
Function-pointer parameters link fine.

---

## Bug: generic types over an interface do not link across a `.moon` boundary

Filed as [namo-robotics/sun#217](https://github.com/namo-robotics/sun/issues/217).

**Labels:** bug, moon, codegen

Companion to the interface-parameter mangling issue. A library exports
`class Server { init(alloc, config: Config, handlers: Vec<IHandler>) }`. A
consumer of the moon that calls it fails at IR verification:

```
Call parameter type does not match function signature!
  %move.val10 = load %"$862e8b55$_std_Vec_$3ee627d5$_sun_serve_IHandler_struct", ...
  invoke void @"...Server_init$...$$862e8b55$_std_Vec_sun_serve_IHandler"(...)
Error: Function verification failed: main
```

The consumer names the specialization `Vec_$hash$_sun_serve_IHandler`, the
moon named it `Vec_sun_serve_IHandler`. Any public API that takes or returns
a generic over an interface is therefore unusable from a moon, which is why
sun_serve's example and command compile the library from source.

---

## Bug: archives carried by a transitive moon are not linked for a consumer

Filed as [namo-robotics/sun#218](https://github.com/namo-robotics/sun/issues/218).

**Labels:** bug, moon, linker

`sun_serve.moon` depends on `tls.moon`, which carries libssl.a/libcrypto.a.
A program listing `libraries: ["stdlib.moon", "tls.moon", "sun_serve.moon"]`
JIT-runs, but `sun -c` fails:

```
ld: main_module:(.text+0x27bff): undefined reference to `ERR_get_error'
```

The OpenSSL symbols referenced from sun_serve.moon's code are not resolved
against the archives tls.moon carries, most likely a link-order problem
(archives placed before the objects that need them, or only the direct
importer's archives being passed to the linker).

---

## Bug: passing a class where an interface value is expected is inconsistent

Filed as [namo-robotics/sun#219](https://github.com/namo-robotics/sun/issues/219).

**Labels:** bug, semantic-analysis

`Vec<IHandler>.push(Impl())` converts implicitly, but a constructor or method
parameter of type `IHandler` does not:

```
No matching constructor for 'W' with arguments (HeapAllocator, Bump)
       candidate: init(ref HeapAllocator, IHandler)
```

Workaround: `var h: IHandler = Bump(); W(alloc, h);`. Either both should
convert or neither.

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

## Bug: `using std;` at file scope is not visible inside a module body

Filed as [namo-robotics/sun#221](https://github.com/namo-robotics/sun/issues/221).

**Labels:** bug, name-resolution

With `using std;` only at the top of the file, a class inside `module spike`
fails on `this.path = String(alloc, "/")` with

```
Cannot assign value of type 'String' to field 'path' of type 'String'
```

Adding `using std;` inside the module block fixes it. Either the file-level
directive should apply to nested modules or the diagnostic should say that
two different `String` types are involved.

---

## Feature: block bodies in `match` arms

Filed as [namo-robotics/sun#222](https://github.com/namo-robotics/sun/issues/222).

**Labels:** enhancement, parser

```sun
match config.tls {
  Option.Some(spec) => { load(spec); loaded = true; }
  Option.None => { }
}
```

fails with `expected ',' or '}' in match expression`. `match` is
expression-only, so any arm needing more than one statement has to be
factored into a helper and every match has to yield a value.

---

## Bug (stdlib): `TcpStream`/`TcpListener`/`UdpSocket` close fd 0 when zeroed

Filed as [namo-robotics/sun#223](https://github.com/namo-robotics/sun/issues/223).

**Labels:** bug, stdlib

Moved-from values are zeroed and still run `deinit` (documented in
`shared_tests.sun`; `std.io.File` uses `0` as "holds nothing" for this
reason). The socket classes use `-1` as the closed sentinel and `close()`
tests `fd >= 0`, so a zeroed `TcpStream` in a `Vec` slot after `take()`, or
in any moved-from position, shuts down and closes descriptor 0 (stdin).
Suggested fix: adopt the `File` convention (`fd > 0`) in networking.sun.

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

## Bug (build): installed `stdlib.moon`/`tls.moon` are x86_64 only

Filed as [namo-robotics/sun#227](https://github.com/namo-robotics/sun/issues/227).

**Labels:** bug, packaging

```
sun -c --target aarch64-linux-musl -o out prog.sun
Semantic Error: Failed to link precompiled module: Module '03a4...' was compiled for
'x86_64-pc-linux-gnu' but the current target is 'aarch64-linux-musl'
```

The Debian package should ship per-target moons (or the driver should build
them on demand from `/usr/share/sun/stdlib`) so the documented
`--target aarch64-linux-gnu` flow works out of the box.

---

## Performance (stdlib): `ContiguousBuffer.get_unchecked` is 3x slower than a raw load

Filed as [namo-robotics/sun#228](https://github.com/namo-robotics/sun/issues/228).

**Labels:** performance, stdlib

Scanning 100 MB byte by byte: `get_unchecked(i)` 189 ms, `_load<u8>(p, i)` in
`unsafe` 67 ms (compiled with `sun -c`). The parser in sun_serve uses raw
loads because of this, which spreads `unsafe` into otherwise safe code. The
accessor should inline to a single load.

Related: `ContiguousBuffer.resize_to` copies element by element with
`_load/_store` instead of `_memcpy`, and there is no `_memmove` intrinsic for
overlapping ranges (buffer compaction needs a temporary copy).

---

## Feature (stdlib): byte access on `const ref String`, numeric `eprint`

Filed as [namo-robotics/sun#229](https://github.com/namo-robotics/sun/issues/229).

**Labels:** enhancement, stdlib

- `String.data` is private and `c_str()` needs `ref`, so a `const ref String`
  cannot hand its bytes to a C call or a `_memcpy`; callers copy byte by byte
  with `at(i)`. A `const method bytes() raw_ptr<u8>` would fix this.
- `eprint`/`eprintln` have only string overloads (`print` has numeric ones),
  so error paths format numbers through a temporary `String`.

---

## Docs: `sun-config.json` keys

Filed as [namo-robotics/sun#230](https://github.com/namo-robotics/sun/issues/230).

**Labels:** docs

The modules page documents `sunPath` / `pathVariables`; the compiler
(`sun --help`) reads `sun_path` / `path_variables` / `entrypoints`. The docs
should use the snake_case names and describe `entrypoints` and `--target`
interaction with per-target moons.
