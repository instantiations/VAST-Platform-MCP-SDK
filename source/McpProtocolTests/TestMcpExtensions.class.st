Class {
	#name : 'TestMcpExtensions',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'client'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Running' }
TestMcpExtensions >> setUp [
	"Prepare server and client."

	super setUp.
	server := McpServer new.
	client := McpClient forServer: server
]

{ #category : 'Running' }
TestMcpExtensions >> tearDown [
	"Clean up."

	client ifNotNil: [client close].
	super tearDown
]

{ #category : 'Testing' }
TestMcpExtensions >> testAppsExtensionAddsHtmlResourceAndTool [
	"Verify MCP Apps extension registers ui:// HTML resources and annotates tools."

	| apps tool |

	apps := McpAppsExtension new.
	apps addHtmlResource: 'ui://clock/app.html' html: '<html><body>Clock</body></html>'.

	tool :=
		McpBlockTool new
			name: 'get_time';
			block: ['12:00:00'];
			yourself.
	apps addTool: tool resourceUri: 'ui://clock/app.html'.
	apps validate.
	server addExtension: apps.

	self assert: (server resourceRegistry includesResourceAt: 'ui://clock/app.html').
	self assert: (server toolRegistry includesToolNamed: 'get_time').
	self assert: ((tool meta at: 'ui') at: 'resourceUri') equals: 'ui://clock/app.html'.
	self assert: ((tool meta at: 'ui') at: 'visibility') equals: 'model'
]

{ #category : 'Testing' }
TestMcpExtensions >> testAppsExtensionResourceReadAnswersValidResourceResult [
	"Verify MCP Apps HTML resource returns a valid resource contents dictionary when read."

	| apps readResult contents firstItem |

	apps := McpAppsExtension new.
	apps addHtmlResource: 'ui://clock/app.html' html: '<html><body>Clock</body></html>'.
	server addExtension: apps.

	readResult :=
		server
			resourcesRead: (EsOrderedDictionary with: 'uri' -> 'ui://clock/app.html')
			context: nil.
	self assert: (readResult isKindOf: KeyedCollection).
	contents := readResult at: 'contents'.
	self assert: (contents isKindOf: SequenceableCollection).
	self assert: contents size equals: 1.
	firstItem := contents first.
	self assert: (firstItem at: 'uri') equals: 'ui://clock/app.html'.
	self assert: (firstItem at: 'mimeType') equals: 'text/html;profile=mcp-app'.
	self assert: (firstItem at: 'text') equals: '<html><body>Clock</body></html>'
]

{ #category : 'Testing' }
TestMcpExtensions >> testAppsExtensionValidationRejectsMissingResource [
	"Verify MCP Apps validation rejects tools referencing unregistered UI resources."

	| apps tool |

	apps := McpAppsExtension new.
	tool :=
		McpBlockTool new
			name: 'orphan_tool';
			block: ['val'];
			yourself.
	apps addTool: tool resourceUri: 'ui://missing/app.html'.

	self should: [apps validate] raise: Error
]

{ #category : 'Testing' }
TestMcpExtensions >> testClientAdvertisesExtensions [
	"Verify client declares extensions in client capabilities."

	| ext caps |

	ext :=
		McpExtension
			identifier: 'io.modelcontextprotocol/ui'
			settings: (EsOrderedDictionary with: 'mimeTypes' -> #('text/html;profile=mcp-app')).
	client addExtension: ext.

	caps := client capabilities.
	self assert: (caps includesKey: 'extensions').
	self assert: ((caps at: 'extensions') includesKey: 'io.modelcontextprotocol/ui')
]

{ #category : 'Testing' }
TestMcpExtensions >> testClientSupportsApps [
	"Verify clientSupportsApps detects declared extension and text/html;profile=mcp-app MIME type."

	| ctx settings |

	ctx := McpServerRequestContext new.
	self deny: (McpAppsExtension clientSupportsApps: ctx).

	settings := EsOrderedDictionary with: 'mimeTypes' -> #('text/html;profile=mcp-app').
	ctx clientCapabilities: (
		EsOrderedDictionary with:
			'extensions' -> (EsOrderedDictionary with: 'io.modelcontextprotocol/ui' -> settings)).
	self assert: (McpAppsExtension clientSupportsApps: ctx).

	settings at: 'mimeTypes' put: #('text/plain').
	self deny: (McpAppsExtension clientSupportsApps: ctx)
]

{ #category : 'Testing' }
TestMcpExtensions >> testRequireClientExtensionFailsWith32021 [
	"Verify requireClientExtension signals -32021 when client omitted the extension."

	| ctx errorSignaled |

	ctx := McpServerRequestContext new.
	ctx clientCapabilities: EsOrderedDictionary new.
	errorSignaled := false.

	[server requireClientExtension: 'io.modelcontextprotocol/ui' context: ctx]
		on: McpJsonRpcError
		do: [:err |
			errorSignaled := true.
			self assert: err code equals: -32021.
			self assert: (err data includesKey: 'requiredCapabilities')].
	self assert: errorSignaled
]

{ #category : 'Testing' }
TestMcpExtensions >> testRequireClientExtensionSucceeds [
	"Verify requireClientExtension succeeds when client advertised the extension."

	| ctx |

	ctx := McpServerRequestContext new.
	ctx clientCapabilities: (
		EsOrderedDictionary with:
			'extensions' ->
				(EsOrderedDictionary with: 'io.modelcontextprotocol/ui' -> EsOrderedDictionary new)).

	server requireClientExtension: 'io.modelcontextprotocol/ui' context: ctx.
	self assert: true
]

{ #category : 'Testing' }
TestMcpExtensions >> testServerAdvertisesExtensions [
	"Verify server advertises declared extensions under capabilities."

	| ext caps |

	ext :=
		McpExtension
			identifier: 'com.example/test-ext'
			settings: (EsOrderedDictionary with: 'enabled' -> true).
	server addExtension: ext.

	caps := server capabilities.
	self assert: (caps includesKey: 'extensions').
	self assert: (((caps at: 'extensions') at: 'com.example/test-ext') at: 'enabled') equals: true
]

{ #category : 'Testing' }
TestMcpExtensions >> testValidateExtensionIdentifier [
	"Verify reverse-DNS identifier validation per SEP-2133."

	self assert: (McpExtension validateExtensionIdentifier: 'io.modelcontextprotocol/ui').
	self assert: (McpExtension validateExtensionIdentifier: 'com.example/custom-ext').
	self assert: (McpExtension validateExtensionIdentifier: 'org.vast/feature_1').

	self deny: (McpExtension validateExtensionIdentifier: 'ui').
	self deny: (McpExtension validateExtensionIdentifier: 'no-domain/name').
	self deny: (McpExtension validateExtensionIdentifier: 'io.modelcontextprotocol/').
	self deny: (McpExtension validateExtensionIdentifier: '/name')
]
