"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpProtocol

`VastMcpProtocol` defines the loadable module for MCP client, JSON-RPC, and
request-context contracts.

## Responsibilities

- Own protocol lifecycle, correlation, errors, and request context.
- Remain independent of HTTP and concrete prompt or tool implementations.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpProtocol',
	#superclass : 'SubApplication',
	#category : 'McpProtocol'
}
