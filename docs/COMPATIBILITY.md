# Compatibility and upstream reference

## Version mapping

| Production map | Python SDK reference |
| --- | --- |
| `1.0.0` | `v2.2.0` |

The 1.0.0 reference is
[python-sdk v2.2.0](https://github.com/modelcontextprotocol/python-sdk/tree/v2.2.0),
commit `9972c21aa42054fb1450c5fc614761ed11847ec6`. The preceding reference is
`v2.1.1`, commit `0921d94a74db900dccd2d534842aa7b6160542d2`.

These are porting references, not Python runtime dependencies or certification
of complete SDK equivalence. VAST MCP uses native Smalltalk protocols and
libraries rather than Python-specific representations such as Pydantic models.

## Protocol targets

The implementation targets `2026-07-28` and retains compatibility paths for
`2025-11-25`, `2025-06-18`, `2025-03-26`, and `2024-11-05`.
Available behavior depends on the negotiated protocol and transport.
Record successful client/server combinations in the release validation record.
