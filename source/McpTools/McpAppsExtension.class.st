"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpAppsExtension

`McpAppsExtension` implements the MCP Apps UI extension (`io.modelcontextprotocol/ui`).

## Responsibilities

- Register interactive HTML resources under the `ui://` scheme with MIME type
  `text/html;profile=mcp-app`.
- Annotate tools with `_meta.ui` (`resourceUri` and `visibility: 'model' | 'app'`).
- Validate that all UI tools reference registered extension resources (`validate`).
- Determine client support via `clientSupportsApps:`.

## Lifecycle and boundaries

Subclass of `McpExtension`. Registered on an `McpServer`.
"
Class {
	#name : 'McpAppsExtension',
	#superclass : 'McpExtension',
	#instVars : [
		'tools',
		'resources'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpTools'
}

{ #category : 'Constants' }
McpAppsExtension class >> appMimeType [
	"Answer the standard MIME type for interactive UI documents.

	 Answers:
		<String>."

	^'text/html;profile=mcp-app'
]

{ #category : 'Testing' }
McpAppsExtension class >> clientSupportsApps: aRequestContext [
	"Answer whether the client negotiated the MCP Apps extension and its MIME type.

	 Arguments:
		aRequestContext - <McpServerRequestContext> or nil.
	 Answers:
		<Boolean>."

	| capabilities extensions settings mimeTypes |

	aRequestContext ifNil: [^false].
	capabilities := aRequestContext clientCapabilities.
	capabilities ifNil: [^false].
	extensions := capabilities at: 'extensions' ifAbsent: [nil].
	extensions ifNil: [^false].
	settings := extensions at: self extensionId ifAbsent: [nil].
	settings ifNil: [^false].
	mimeTypes := settings at: 'mimeTypes' ifAbsent: [nil].
	(mimeTypes isCollection and: [mimeTypes isString not]) ifFalse: [^false].
	^mimeTypes includes: self appMimeType
]

{ #category : 'Constants' }
McpAppsExtension class >> extensionId [
	"Answer the standard MCP Apps reverse-DNS extension identifier.

	 Answers:
		<String>."

	^'io.modelcontextprotocol/ui'
]

{ #category : 'Registration' }
McpAppsExtension >> addHtmlResource: aUri html: htmlString [
	"Register an interactive HTML UI resource at a ui:// URI.

	 Arguments:
		aUri - <String> URI starting with 'ui://'.
		htmlString - <String> HTML document contents.
	 Answers:
		<McpAppsExtension> the receiver."

	| resource |

	(aUri isString and: [aUri beginsWithSubCollection: 'ui://'])
		ifFalse: [self error: 'MCP Apps resources must use the ui:// scheme: ' , aUri printString].
	resource :=
		McpBlockResource new
			uri: aUri;
			name: (aUri copyFrom: 6 to: aUri size);
			mimeType: self class appMimeType;
			block: [
				EsOrderedDictionary with: 'contents' -> (Array with: (
					EsOrderedDictionary new
						at: 'uri' put: aUri copy;
						at: 'mimeType' put: self class appMimeType;
						at: 'text' put: htmlString copy;
						yourself))];
			yourself.
	self resources add: resource.
	^self
]

{ #category : 'Registration' }
McpAppsExtension >> addTool: aTool resourceUri: aUri [
	"Register an MCP tool bound to an interactive UI resource with default 'model' visibility.

	 Arguments:
		aTool - <McpTool>.
		aUri - <String>.
	 Answers:
		<McpAppsExtension> the receiver."

	^self addTool: aTool resourceUri: aUri visibility: 'model'
]

{ #category : 'Registration' }
McpAppsExtension >> addTool: aTool resourceUri: aUri visibility: aVisibilityString [
	"Register an MCP tool bound to an interactive UI resource.

	 Arguments:
		aTool - <McpTool> tool instance.
		aUri - <String> URI starting with 'ui://'.
		aVisibilityString - <String> 'model' or 'app'.
	 Answers:
		<McpAppsExtension> the receiver."

	| currentMeta uiMeta |

	(aUri isString and: [aUri beginsWithSubCollection: 'ui://'])
		ifFalse: [self error: 'MCP Apps tool resourceUri must use ui:// scheme: ' , aUri printString].
	uiMeta :=
		EsOrderedDictionary new
			at: 'resourceUri' put: aUri copy;
			at: 'visibility' put: aVisibilityString copy;
			yourself.
	currentMeta := aTool meta ifNil: [EsOrderedDictionary new] ifNotNil: [aTool meta copy].
	currentMeta at: 'ui' put: uiMeta.
	aTool meta: currentMeta.
	self tools add: aTool.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpAppsExtension >> initialize [
	"Initialize the MCP Apps extension state.

	 Answers:
		<McpAppsExtension> the receiver."

	super initialize.
	self identifier: self class extensionId.
	tools := OrderedCollection new.
	resources := OrderedCollection new.
	^self
]

{ #category : 'Accessing' }
McpAppsExtension >> resources [
	"Answer the UI HTML resources contributed by this extension.

	 Answers:
		<OrderedCollection> of <McpResource>."

	resources ifNil: [resources := OrderedCollection new].
	^resources
]

{ #category : 'Accessing' }
McpAppsExtension >> tools [
	"Answer the UI-bound tools contributed by this extension.

	 Answers:
		<OrderedCollection> of <McpTool>."

	tools ifNil: [tools := OrderedCollection new].
	^tools
]

{ #category : 'Validation' }
McpAppsExtension >> validate [
	"Verify that every registered tool's resourceUri has a corresponding registered resource.

	 Answers:
		<McpAppsExtension> the receiver."

	| registeredUris toolUri |

	registeredUris := self resources collect: [:res | res uri].
	self tools do: [:tool |
		toolUri :=
			(tool meta at: 'ui' ifAbsent: [EsOrderedDictionary new])
				at: 'resourceUri'
				ifAbsent: [nil].
		toolUri ifNotNil: [
			(registeredUris includes: toolUri)
				ifFalse: [
					self error:
						'MCP Apps tool ' , tool name printString , ' binds resourceUri ' ,
							toolUri printString ,
							', but no such resource is registered on this extension']]].
	^self
]
