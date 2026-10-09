"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpServerResources

`TestMcpServerResources` verifies the MCP server resource protocol.

## Responsibilities

- Verify concrete-resource and template listing with cursor pagination.
- Verify text and binary resource reads.
- Verify concrete-resource precedence and template fallback.
- Verify URI, result, not-found, and cursor error behavior.
- Verify request-context propagation to resource readers.

Each test creates fresh server registries and a dispatcher. Tests perform no
network I/O and create no background work.
"
Class {
	#name : 'TestMcpServerResources',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher',
		'resourceRegistry',
		'templateRegistry'
	],
	#category : 'McpResourceTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> assertErrorResponse: response code: expectedCode id: expectedIdentifier [
	"Assert the complete structural contract of a JSON-RPC error response."

	| error |

	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier.
	self deny: (response includesKey: 'result').
	error := response at: 'error'.
	self assert: (error at: 'code') equals: expectedCode.
	self assert: (error at: 'message') isString.
	self deny: (error at: 'message') isEmpty
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> assertSuccessfulResponse: response id: expectedIdentifier [
	"Assert the structural contract of a JSON-RPC result response."

	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier.
	self assert: (response includesKey: 'result').
	self deny: (response includesKey: 'error')
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> blobReadResultUri: uri mimeType: mimeType blob: blob [
	"Answer a ReadResourceResult containing one binary content object."

	| content |

	content :=
		EsOrderedDictionary new
			at: 'uri' put: uri;
			at: 'mimeType' put: mimeType;
			at: 'blob' put: blob;
			yourself.
	^EsOrderedDictionary with: 'contents' -> (Array with: content)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> emptyReadResult [
	"Answer a valid empty ReadResourceResult."

	^EsOrderedDictionary with: 'contents' -> #()
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> requestMethod: methodName params: parameters id: identifier [
	"Answer a JSON-RPC request fixture."

	| request |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'method' put: methodName;
			yourself.
	parameters ifNotNil: [request at: 'params' put: parameters].
	^request
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> resourceAt: uri name: resourceName block: readerBlock [
	"Answer a configured concrete block resource."

	^McpBlockResource new
		uri: uri;
		name: resourceName;
		block: readerBlock;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> resourceReadRequestUri: uri id: identifier [
	"Answer a resources/read request fixture."

	^self
		requestMethod: 'resources/read'
		params: (EsOrderedDictionary with: 'uri' -> uri)
		id: identifier
]

{ #category : 'Initialization' }
TestMcpServerResources >> setUp [
	"Create fresh server registries and a dispatcher."

	super setUp.
	server := McpServer new.
	resourceRegistry := server resourceRegistry.
	templateRegistry := server resourceTemplateRegistry.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: server
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> template: templateString name: templateName match: matcher read: reader [
	"Answer a configured block resource template."

	^McpBlockResourceTemplate new
		uriTemplate: templateString;
		name: templateName;
		matchBlock: matcher;
		readBlock: reader;
		yourself
]

{ #category : 'Protocol Operations' }
TestMcpServerResources >> testConcreteResourceTakesPrecedenceOverMatchingTemplate [
	"An exact concrete resource is read before a matching template."

	| resource template response result |

	resource :=
		self
			resourceAt: 'test://items/42'
			name: 'concrete'
			block: [self textReadResultUri: 'test://items/42' text: 'concrete'].
	template :=
		self
			template: 'test://items/{id}'
			name: 'template'
			match: [:uri | uri = 'test://items/42']
			read: [:uri | self textReadResultUri: uri text: 'template'].
	resourceRegistry registerResource: resource.
	templateRegistry registerTemplate: template.
	response := dispatcher dispatch: (self resourceReadRequestUri: 'test://items/42' id: 1).
	self assertSuccessfulResponse: response id: 1.
	result := response at: 'result'.
	self assert: ((result at: 'contents') first at: 'text') equals: 'concrete'
]

{ #category : 'Protocol Operations' }
TestMcpServerResources >> testEmptyResourceListingsReturnCompleteResults [
	"Empty concrete and template registries return complete list results."

	| response result |

	response := dispatcher dispatch: (self requestMethod: 'resources/list' params: nil id: 2).
	self assertSuccessfulResponse: response id: 2.
	result := response at: 'result'.
	self assert: result size equals: 1.
	self assert: (result at: 'resources') isEmpty.
	response :=
		dispatcher dispatch: (self requestMethod: 'resources/templates/list' params: nil id: 3).
	self assertSuccessfulResponse: response id: 3.
	result := response at: 'result'.
	self assert: result size equals: 1.
	self assert: (result at: 'resourceTemplates') isEmpty
]

{ #category : 'Error Handling' }
TestMcpServerResources >> testModernResourceNotFoundSignals32602 [
	"In modern protocol version 2026-07-28, resource not found returns -32602 instead of -32002."

	| request response error |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 501;
			at: 'method' put: 'resources/read';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'uri' put: 'file:///nonexistent.txt';
						at: '_meta'
							put: (
								EsOrderedDictionary new
									at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
									yourself);
						yourself);
			yourself.
	response := dispatcher dispatch: request.
	self assert: (response at: 'id') equals: 501.
	error := response at: 'error'.
	self assert: (error at: 'code') equals: -32602.
	self assert: ((error at: 'data') at: 'uri') equals: 'file:///nonexistent.txt'
]

{ #category : 'Protocol Operations' }
TestMcpServerResources >> testReadConcreteBinaryResource [
	"A concrete resource may return one binary blob content object."

	| resource response content |

	resource :=
		self
			resourceAt: 'test://images/logo'
			name: 'logo'
			block: [
				self
					blobReadResultUri: 'test://images/logo'
					mimeType: 'image/png'
					blob: 'iVBORw0KGgo='].
	resourceRegistry registerResource: resource.
	response := dispatcher dispatch: (self resourceReadRequestUri: 'test://images/logo' id: 4).
	self assertSuccessfulResponse: response id: 4.
	content := ((response at: 'result') at: 'contents') first.
	self assert: (content at: 'uri') equals: 'test://images/logo'.
	self assert: (content at: 'mimeType') equals: 'image/png'.
	self assert: (content at: 'blob') equals: 'iVBORw0KGgo='.
	self deny: (content includesKey: 'text')
]

{ #category : 'Dispatching' }
TestMcpServerResources >> testReadConcreteResourcePassesRequestContext [
	"A concrete resource reader receives the dispatcher request context."

	| resource requestContext capturedContext response |

	requestContext := McpServerRequestContext new.
	resource :=
		self
			resourceAt: 'test://resources/context'
			name: 'context'
			block: [:context |
				capturedContext := context.
				self textReadResultUri: 'test://resources/context' text: 'context received'].
	resourceRegistry registerResource: resource.
	response :=
		dispatcher
			dispatch: (self resourceReadRequestUri: 'test://resources/context' id: 5)
			context: requestContext.
	self assertSuccessfulResponse: response id: 5.
	self assert: capturedContext == requestContext
]

{ #category : 'Validation' }
TestMcpServerResources >> testReadMalformedResourceResultBecomesInternalError [
	"A reader result containing both text and blob is rejected."

	| resource malformedContent malformedResult response |

	malformedContent :=
		EsOrderedDictionary new
			at: 'uri' put: 'test://resources/malformed';
			at: 'text' put: 'text';
			at: 'blob' put: 'blob';
			yourself.
	malformedResult := EsOrderedDictionary with: 'contents' -> (Array with: malformedContent).
	resource :=
		self resourceAt: 'test://resources/malformed' name: 'malformed' block: [malformedResult].
	resourceRegistry registerResource: resource.
	response := dispatcher
		dispatch: (self resourceReadRequestUri: 'test://resources/malformed' id: 6).
	self assertErrorResponse: response code: -32603 id: 6
]

{ #category : 'Validation' }
TestMcpServerResources >> testReadRejectsMalformedResourceUri [
	"A resources/read request requires an absolute URI."

	| response |

	response := dispatcher dispatch: (self resourceReadRequestUri: 'relative/path' id: 7).
	self assertErrorResponse: response code: -32602 id: 7
]

{ #category : 'Error Handling' }
TestMcpServerResources >> testReadUnknownResourceReturnsNotFoundError [
	"An unknown resource produces the MCP resource-not-found error."

	| response error |

	response := dispatcher dispatch: (self resourceReadRequestUri: 'test://resources/missing' id: 8).
	self assertErrorResponse: response code: -32602 id: 8.
	error := response at: 'error'.
	self assert: (error at: 'message') equals: 'Resource not found'.
	self assert: ((error at: 'data') at: 'uri') equals: 'test://resources/missing'
]

{ #category : 'Protocol Operations' }
TestMcpServerResources >> testResourceListingPaginatesWithoutOrderAssumptions [
	"Cursor pagination returns every concrete resource exactly once."

	| firstResponse secondResponse firstResult secondResult firstResources secondResources names
	  cursor parameters |

	#('test://resources/zeta' 'test://resources/alpha' 'test://resources/middle') do: [:uri |
		resourceRegistry
			registerResource: (self resourceAt: uri name: uri block: [self emptyReadResult])].
	server listPageSize: 2.
	firstResponse := dispatcher dispatch: (self requestMethod: 'resources/list' params: nil id: 9).
	self assertSuccessfulResponse: firstResponse id: 9.
	firstResult := firstResponse at: 'result'.
	firstResources := firstResult at: 'resources'.
	self assert: firstResources size equals: 2.
	cursor := firstResult at: 'nextCursor'.
	parameters := EsOrderedDictionary with: 'cursor' -> cursor.
	secondResponse :=
		dispatcher dispatch: (self requestMethod: 'resources/list' params: parameters id: 10).
	self assertSuccessfulResponse: secondResponse id: 10.
	secondResult := secondResponse at: 'result'.
	secondResources := secondResult at: 'resources'.
	self assert: secondResources size equals: 1.
	self deny: (secondResult includesKey: 'nextCursor').
	names := Set new.
	firstResources do: [:definition | names add: (definition at: 'uri')].
	secondResources do: [:definition | names add: (definition at: 'uri')].
	self assert: names size equals: 3.
	self assert: (names includes: 'test://resources/zeta').
	self assert: (names includes: 'test://resources/alpha').
	self assert: (names includes: 'test://resources/middle')
]

{ #category : 'Validation' }
TestMcpServerResources >> testResourceListingRejectsMalformedCursor [
	"A malformed concrete-resource cursor is an invalid parameter."

	| parameters response |

	parameters := EsOrderedDictionary with: 'cursor' -> 'not-a-cursor'.
	response := dispatcher dispatch: (self requestMethod: 'resources/list' params: parameters id: 11).
	self assertErrorResponse: response code: -32602 id: 11
]

{ #category : 'Protocol Operations' }
TestMcpServerResources >> testResourceTemplateListingPaginatesWithoutOrderAssumptions [
	"Cursor pagination returns every resource template exactly once."

	| firstResponse secondResponse firstResult secondResult firstTemplates secondTemplates names
	  cursor parameters |

	#('test://zeta/{id}' 'test://alpha/{id}' 'test://middle/{id}') do: [:templateString |
		templateRegistry registerTemplate: (
			self
				template: templateString
				name: templateString
				match: [:uri | false]
				read: [:uri | self emptyReadResult])].
	server listPageSize: 2.
	firstResponse :=
		dispatcher dispatch: (self requestMethod: 'resources/templates/list' params: nil id: 12).
	self assertSuccessfulResponse: firstResponse id: 12.
	firstResult := firstResponse at: 'result'.
	firstTemplates := firstResult at: 'resourceTemplates'.
	self assert: firstTemplates size equals: 2.
	cursor := firstResult at: 'nextCursor'.
	parameters := EsOrderedDictionary with: 'cursor' -> cursor.
	secondResponse :=
		dispatcher
			dispatch: (self requestMethod: 'resources/templates/list' params: parameters id: 13).
	self assertSuccessfulResponse: secondResponse id: 13.
	secondResult := secondResponse at: 'result'.
	secondTemplates := secondResult at: 'resourceTemplates'.
	self assert: secondTemplates size equals: 1.
	self deny: (secondResult includesKey: 'nextCursor').
	names := Set new.
	firstTemplates do: [:definition | names add: (definition at: 'uriTemplate')].
	secondTemplates do: [:definition | names add: (definition at: 'uriTemplate')].
	self assert: names size equals: 3.
	self assert: (names includes: 'test://zeta/{id}').
	self assert: (names includes: 'test://alpha/{id}').
	self assert: (names includes: 'test://middle/{id}')
]

{ #category : 'Dispatching' }
TestMcpServerResources >> testTemplateReadPassesUriAndRequestContext [
	"A matching template reader receives concrete URI and request context."

	| template requestContext capturedUri capturedContext response content |

	requestContext := McpServerRequestContext new.
	template :=
		self
			template: 'test://items/{id}'
			name: 'items'
			match: [:uri | uri = 'test://items/42']
			read: [:uri :context |
				capturedUri := uri.
				capturedContext := context.
				self textReadResultUri: uri text: 'template value'].
	templateRegistry registerTemplate: template.
	response :=
		dispatcher
			dispatch: (self resourceReadRequestUri: 'test://items/42' id: 14)
			context: requestContext.
	self assertSuccessfulResponse: response id: 14.
	self assert: capturedUri equals: 'test://items/42'.
	self assert: capturedContext == requestContext.
	content := ((response at: 'result') at: 'contents') first.
	self assert: (content at: 'text') equals: 'template value'
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerResources >> textReadResultUri: uri text: text [
	"Answer a ReadResourceResult containing one text content object."

	| content |

	content :=
		EsOrderedDictionary new
			at: 'uri' put: uri;
			at: 'mimeType' put: 'text/plain';
			at: 'text' put: text;
			yourself.
	^EsOrderedDictionary with: 'contents' -> (Array with: content)
]
