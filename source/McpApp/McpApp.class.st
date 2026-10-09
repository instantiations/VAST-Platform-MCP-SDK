"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastMcpApp

`VastMcpApp` defines the loadable module for transport-neutral Model Context
Protocol support.

## Responsibilities

- Own MCP protocol values, prompts, resources, tools, and client contracts.
- Keep HTTP and other transport concerns outside the core protocol module.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'McpApp',
	#superclass : 'Application',
	#category : 'McpApp'
}

{ #category : 'Configuration' }
McpApp class >> _PRAGMA_McpJsonRpcConstants [
	"%%PRAGMA DECLARE
	(name: McpJsonRpcConstants isPool: true)
	(pool: McpJsonRpcConstants declarations: (
		(name: McpJsonRpcParseErrorCode isConstant: true valueExpression: '-32700')
		(name: McpJsonRpcInvalidRequestCode isConstant: true valueExpression: '-32600')
		(name: McpJsonRpcMethodNotFoundCode isConstant: true valueExpression: '-32601')
		(name: McpJsonRpcInvalidParamsCode isConstant: true valueExpression: '-32602')
		(name: McpJsonRpcInternalErrorCode isConstant: true valueExpression: '-32603')
		(name: McpHeaderMismatchErrorCode isConstant: true valueExpression: '-32020')
		(name: McpMissingRequiredClientCapabilityErrorCode isConstant: true valueExpression: '-32021')
		(name: McpUnsupportedProtocolVersionErrorCode isConstant: true valueExpression: '-32022')
		(name: McpResourceNotFoundErrorCode isConstant: true valueExpression: '-32602')
		(name: McpServerNotInitializedErrorCode isConstant: true valueExpression: '-32002')
	))
	"
]
