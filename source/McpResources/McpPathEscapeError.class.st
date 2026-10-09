"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpPathEscapeError

`McpPathEscapeError` is signaled when a filesystem path resolution escapes
its intended sandbox root directory.

## Responsibilities

- Represent path traversal and sandbox escape violations.

## Lifecycle and boundaries

Standard exception subclass of `Error`.
"
Class {
	#name : 'McpPathEscapeError',
	#superclass : 'Error',
	#category : 'McpResources'
}
