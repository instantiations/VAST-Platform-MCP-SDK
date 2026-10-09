"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpResources

`VastMcpResources` defines the loadable module for MCP resource values,
templates, and registries.

## Responsibilities

- Own resource lookup, URI templates, and detached content results.
- Preserve registration identity and validate protocol metadata.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpResources',
	#superclass : 'SubApplication',
	#category : 'McpResources'
}
