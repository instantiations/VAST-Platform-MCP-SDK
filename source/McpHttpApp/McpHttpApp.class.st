"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpHttpApp

`VastMcpHttpApp` defines the loadable module for HTTP and SSE transport
support for MCP.

## Responsibilities

- Own MCP HTTP client, servlet, session, and admission behavior.
- Use SST HTTP facilities while preserving transport-neutral MCP contracts.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpHttpApp',
	#superclass : 'Application',
	#category : 'McpHttpApp'
}
