"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpHttpClient

`VastMcpHttpClient` defines the loadable module for MCP HTTP client
transport and session recovery.

## Responsibilities

- Own outbound JSON-RPC HTTP requests, SSE parsing, and session state.
- Manage client startup, shutdown, correlation, and retry boundaries.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpHttpClientSubApp',
	#superclass : 'SubApplication',
	#category : 'McpHttpClientSubApp'
}
