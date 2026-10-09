"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpPrompts

`VastMcpPrompts` defines the loadable module for MCP prompt values and registry.

## Responsibilities

- Own prompt definitions, argument validation, and rendering.
- Return detached protocol values to preserve registry ownership.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpPrompts',
	#superclass : 'SubApplication',
	#category : 'McpPrompts'
}
