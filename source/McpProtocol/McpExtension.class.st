"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpExtension

`McpExtension` provides a pluggable extension interface for MCP servers and clients
(SEP-2133).

## Responsibilities

- Validate reverse-DNS extension identifiers (`validateExtensionIdentifier:`).
- Contribute bundles of tools, resources, and custom JSON-RPC request methods.
- Provide tool call interception via `interceptToolCall:tool:arguments:context:callNext:`.
- Advertise extension settings under `capabilities.extensions`.

## Lifecycle and boundaries

Subclassed by concrete extensions (e.g., `McpAppsExtension`). Registered on
`McpServer` or `McpClient`.
"
Class {
	#name : 'McpExtension',
	#superclass : 'Object',
	#instVars : [
		'identifier',
		'settings'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpExtension class >> identifier: anIdentifier [
	"Answer a new extension instance with the specified reverse-DNS identifier.

	 Arguments:
		anIdentifier - <String> reverse-DNS identifier.
	 Answers:
		<McpExtension>."

	^self identifier: anIdentifier settings: EsOrderedDictionary new
]

{ #category : 'Instance Creation' }
McpExtension class >> identifier: anIdentifier settings: aDictionary [
	"Answer a new extension instance with the specified identifier and configuration settings.

	 Arguments:
		anIdentifier - <String> reverse-DNS identifier.
		aDictionary - <KeyedCollection> settings dictionary.
	 Answers:
		<McpExtension>."

	(self validateExtensionIdentifier: anIdentifier)
		ifFalse: [
			self error: 'Extension identifier must follow reverse-DNS format: vendor.prefix/name'].
	^self new
		identifier: anIdentifier;
		settings: aDictionary;
		yourself
]

{ #category : 'Instance Creation' }
McpExtension class >> new [
	"Answer a new initialized extension.

	 Answers:
		<McpExtension>."

	^super new initialize
]

{ #category : 'Validation' }
McpExtension class >> validateExtensionIdentifier: anIdentifier [
	"Validate that an extension identifier follows the reverse-DNS format (SEP-2133).
	 Example: 'io.modelcontextprotocol/ui'

	 Arguments:
		anIdentifier - <String>.
	 Answers:
		<Boolean>."

	| slashIndex domain extName |

	(anIdentifier isString and: [anIdentifier notEmpty]) ifFalse: [^false].
	slashIndex := anIdentifier indexOf: $/.
	(slashIndex > 1 and: [slashIndex < anIdentifier size]) ifFalse: [^false].
	domain := anIdentifier copyFrom: 1 to: slashIndex - 1.
	extName := anIdentifier copyFrom: slashIndex + 1 to: anIdentifier size.
	(domain includes: $.) ifFalse: [^false].
	^true
]

{ #category : 'Accessing' }
McpExtension >> identifier [
	"Answer the extension's reverse-DNS identifier string.

	 Answers:
		<String>."

	^identifier
]

{ #category : 'Accessing' }
McpExtension >> identifier: anIdentifier [
	"Set the extension's reverse-DNS identifier string.

	 Arguments:
		anIdentifier - <String>.
	 Answers:
		<McpExtension> the receiver."

	identifier := anIdentifier copy.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpExtension >> initialize [
	"Initialize extension defaults.

	 Answers:
		<McpExtension> the receiver."

	super initialize.
	settings := EsOrderedDictionary new.
	^self
]

{ #category : 'Execution' }
McpExtension >> interceptToolCall: toolCallName
	tool: aTool
	arguments: arguments
	context: requestContext
	callNext: aBlock [
	"Intercept or wrap a tools/call execution. Default implementation passes through unchanged.

	 Arguments:
		toolCallName - <String> tool name.
		aTool - <McpTool> matched tool.
		arguments - <KeyedCollection> tool arguments.
		requestContext - <McpServerRequestContext> or nil.
		aBlock - <Block> evaluation continuation.
	 Answers:
		<Object> execution result."

	^aBlock value
]

{ #category : 'Accessing' }
McpExtension >> resources [
	"Answer the collection of resources contributed by this extension.

	 Answers:
		<Collection> of <McpResource>."

	^#()
]

{ #category : 'Accessing' }
McpExtension >> settings [
	"Answer the settings dictionary advertised under capabilities.extensions[identifier].

	 Answers:
		<KeyedCollection>."

	settings ifNil: [settings := EsOrderedDictionary new].
	^settings
]

{ #category : 'Accessing' }
McpExtension >> settings: aDictionary [
	"Set the settings dictionary advertised under capabilities.extensions[identifier].

	 Arguments:
		aDictionary - <KeyedCollection>.
	 Answers:
		<McpExtension> the receiver."

	settings := aDictionary copy.
	^self
]

{ #category : 'Accessing' }
McpExtension >> tools [
	"Answer the collection of tools contributed by this extension.

	 Answers:
		<Collection> of <McpTool>."

	^#()
]
