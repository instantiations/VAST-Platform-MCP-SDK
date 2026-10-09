"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpToolError

`McpToolError` represents an intentional domain failure raised within a tool execution
block whose message is explicitly intended for the calling model or client.

## Responsibilities

- Signal an actionable tool execution failure without leaking internal stack frames.
- Format cleanly into an MCP `CallToolResult` with `isError: true`.

## Lifecycle and boundaries

Standard exception subclass of `Error`.
"
Class {
	#name : 'McpToolError',
	#superclass : 'Error',
	#category : 'McpTools'
}
