# Agent Development Guide

A file for guiding coding agents.

## Commands

- Never use git commands except readonly ones like `git status` and `git diff`.

## Sun safety boundary

- Do not use `unsafe` or `raw_ptr` in protocol, application, command, example, or test code.
- Keep unavoidable pointer operations inside the audited syscall, ABI, buffer, network, epoll, WebSocket C-binding, transport, signal, and TLS boundary files listed by `scripts/check-sun-safety.sh`.
- Do not expose raw pointers through public APIs. The process entrypoint's `argv` signature is the only exception.
- Wrap each foreign or intrinsic operation in a checked, pointer-free function before calling it from higher-level code.
- Run `scripts/check-sun-safety.sh` when changing Sun code.

## Code Comments
- All code comments should be concise, plain-english written for a general audience of software engineers.
- Use block comments for comments that span multiple lines.
- Put a block comment directly above every module declaration, with no blank line between them.
- Every public function, class, module, etc should have a concise, plain-english block comment describing what it does.
- Do not hard-code numeric values that subject to change in comments.

## Commit messages
- Subject: `<scope>: <description>` (scope = subsystem/package/area; imperative; no `feat`/`fix` types).
- Body: blank line, then one concise bullet per key change if not already captured in the subject.
- Do not add AI attribution to commits or PRs (no Co-Authored-By, Generated-with, tool names, or session links).

## Issues and PR Guidelinese

- Never create PRs or issues unless specifically asked by the user.
