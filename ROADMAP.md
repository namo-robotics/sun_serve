# Roadmap

What sun_serve does not do yet, most important first. Each item is a
self-contained piece of work; nothing here is scheduled.

- **Range requests**
  - Static responses already advertise `Accept-Ranges: bytes`, but a `Range`
    header is ignored and the whole file is sent. Honor it or stop advertising.
  - Needed for resumable downloads and seeking in audio and video.
  - Covers single byte ranges, `If-Range`, and 416 for unsatisfiable ranges.

- **Streaming request bodies**
  - A request body is buffered in full, up to the configured limit, before the
    handler runs. Uploads larger than memory are not possible.
  - Let a handler consume the body as it arrives, with the same timeouts and
    limits the buffered path enforces.

- **`sendfile` for large files**
  - Files are read into user space and written back out. Large plain-HTTP
    responses should hand the copy to the kernel.
  - TLS responses keep the user-space path unless kernel TLS is added later.

- **TLS operations**
  - Reload certificate and key without a restart, so renewals do not drop
    connections.
  - Session resumption to make repeat handshakes cheaper.
  - SNI, so one listener can serve several certificates.

- **Response compression**
  - No `gzip` or `br` today. Compress text-like content types when the client
    asks for it, with precompressed sidecar files for static content.
  - Depends on a compression library being available to the toolchain.

- **Directory listings**
  - A directory without an index file is a 404. Offer an opt-in HTML listing
    with escaped names and sizes.

- **IPv6 and Unix sockets**
  - Listeners are IPv4 only. Accept IPv6 addresses in `--listen` and the
    config, and Unix domain sockets for use behind a local proxy.

- **Observability**
  - Expose per-worker counters (connections, requests, bytes, errors) through
    the library, and optionally on a metrics endpoint.
  - A structured access log format alongside the current one-line form.

- **aarch64 builds**
  - The Dockerfile's dev stage has Ubuntu's aarch64 cross toolchain, but the
    installed Sun stdlib and TLS moons are x86_64 only. Waits on per-target
    moons upstream.
