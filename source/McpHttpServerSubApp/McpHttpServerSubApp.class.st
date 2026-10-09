"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpHttpServer

`VastMcpHttpServer` defines the loadable module for MCP HTTP servlet,
admission, and session protocol.

## Responsibilities

- Own inbound MCP HTTP validation, dispatch, and session lifecycle.
- Reject invalid origins, media types, and protocol sequences early.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpHttpServerSubApp',
	#superclass : 'SubApplication',
	#category : 'McpHttpServerSubApp'
}
