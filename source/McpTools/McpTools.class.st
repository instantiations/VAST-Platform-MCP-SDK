"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpTools

`VastMcpTools` defines the loadable module for MCP tool values, registry,
and block adapters.

## Responsibilities

- Own tool registration, schema exposure, and invocation adapters.
- Reject duplicate names and isolate tool execution failures.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpTools',
	#superclass : 'SubApplication',
	#category : 'McpTools'
}
