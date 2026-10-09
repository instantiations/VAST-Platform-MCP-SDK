"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpClientResources

`TestMcpClientResources` verifies client-side MCP resource operations.

## Responsibilities

- Verify connection and negotiated-capability gating.
- Verify concrete-resource and template pagination.
- Verify advertised resource and URI-template definitions.
- Verify exact `resources/read` request construction.
- Verify text and blob result validation and mutable-value isolation.

Each test creates a new client and `McpScriptedClientTransport`. Tests perform
no network I/O, create no background work, and make no timing assumptions.
"
Class {
	#name : 'TestMcpClientResources',
	#superclass : 'TestCase',
	#instVars : [
		'client',
		'transport'
	],
	#category : 'McpResourceTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientResources >> blobReadResultUri: uri mimeType: mimeType blob: blob [
	"Answer a ReadResourceResult containing one binary object."

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
TestMcpClientResources >> connectWithCapabilities: capabilities [
	"Connect using the supplied server capability declaration."

	transport enqueueResponse: (self initializeResultWith: capabilities).
	client connect
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientResources >> connectWithResourcesCapability [
	"Connect to a server advertising the resources capability."

	self connectWithCapabilities: (EsOrderedDictionary with: 'resources' -> EsOrderedDictionary new)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientResources >> initializeResultWith: capabilities [
	"Answer a valid initialization result with supplied capabilities."

	^EsOrderedDictionary new
		at: 'protocolVersion' put: '2025-11-25';
		at: 'capabilities' put: capabilities;
		at: 'serverInfo'
			put: (
				EsOrderedDictionary
					with: 'name' -> 'ScriptedResourceServer'
					with: 'version' -> '1.0.0');
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientResources >> resourceDefinitionUri: uri name: resourceName [
	"Answer a minimally valid concrete resource definition."

	^EsOrderedDictionary new
		at: 'uri' put: uri;
		at: 'name' put: resourceName;
		yourself
]

{ #category : 'Initialization' }
TestMcpClientResources >> setUp [
	"Create a fresh client and scripted transport."

	super setUp.
	transport := McpScriptedClientTransport new.
	client := McpClient new.
	client transport: transport
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientResources >> templateDefinition: uriTemplate [
	"Answer a minimally valid resource-template definition."

	^EsOrderedDictionary new
		at: 'uriTemplate' put: uriTemplate;
		at: 'name' put: uriTemplate;
		yourself
]

{ #category : 'Protocol Operations' }
TestMcpClientResources >> testListResourceTemplatesCollectsEveryPageWithoutOrderAssumptions [
	"The client follows cursors and aggregates every resource template."

	| firstPage secondPage templates names firstRequest secondRequest |

	self connectWithResourcesCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'resourceTemplates'
				put: (
					Array
						with: (self templateDefinition: 'test://zeta/{id}')
						with: (self templateDefinition: 'test://alpha/{id}'));
			at: 'nextCursor' put: 'page-2';
			yourself.
	secondPage :=
		EsOrderedDictionary with:
			'resourceTemplates' -> (Array with: (self templateDefinition: 'test://middle/{id}')).
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	templates := client listResourceTemplates.
	self assert: templates size equals: 3.
	names := Set new.
	templates do: [:definition | names add: (definition at: 'uriTemplate')].
	self assert: (names includes: 'test://zeta/{id}').
	self assert: (names includes: 'test://alpha/{id}').
	self assert: (names includes: 'test://middle/{id}').
	self assert: transport requests size equals: 3.
	firstRequest := transport requests at: 2.
	secondRequest := transport requests at: 3.
	self assert: (firstRequest at: 'method') equals: 'resources/templates/list'.
	self assert: (firstRequest at: 'params') isEmpty.
	self assert: (secondRequest at: 'method') equals: 'resources/templates/list'.
	self assert: ((secondRequest at: 'params') at: 'cursor') equals: 'page-2'
]

{ #category : 'Validation' }
TestMcpClientResources >> testListResourceTemplatesRejectsMalformedDefinition [
	"The client rejects an invalid URI-template definition."

	| definition page |

	self connectWithResourcesCapability.
	definition := self templateDefinition: 'relative/{id}'.
	page := EsOrderedDictionary with: 'resourceTemplates' -> (Array with: definition).
	transport enqueueResponse: page.
	self should: [client listResourceTemplates] raise: Error
]

{ #category : 'Validation' }
TestMcpClientResources >> testListResourceTemplatesRequiresResourcesCapability [
	"Template listing requires the server resources capability."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client listResourceTemplates] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Protocol Operations' }
TestMcpClientResources >> testListResourcesCollectsEveryPageWithoutOrderAssumptions [
	"The client follows cursors and aggregates every concrete resource."

	| firstPage secondPage resources uris firstRequest secondRequest |

	self connectWithResourcesCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'resources'
				put: (
					Array
						with: (self resourceDefinitionUri: 'test://resources/zeta' name: 'zeta')
						with: (self resourceDefinitionUri: 'test://resources/alpha' name: 'alpha'));
			at: 'nextCursor' put: 'page-2';
			yourself.
	secondPage :=
		EsOrderedDictionary with:
			'resources' ->
				(Array with: (self resourceDefinitionUri: 'test://resources/middle' name: 'middle')).
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	resources := client listResources.
	self assert: resources size equals: 3.
	uris := Set new.
	resources do: [:definition | uris add: (definition at: 'uri')].
	self assert: (uris includes: 'test://resources/zeta').
	self assert: (uris includes: 'test://resources/alpha').
	self assert: (uris includes: 'test://resources/middle').
	self assert: transport requests size equals: 3.
	firstRequest := transport requests at: 2.
	secondRequest := transport requests at: 3.
	self assert: (firstRequest at: 'method') equals: 'resources/list'.
	self assert: (firstRequest at: 'params') isEmpty.
	self assert: (secondRequest at: 'method') equals: 'resources/list'.
	self assert: ((secondRequest at: 'params') at: 'cursor') equals: 'page-2'
]

{ #category : 'Validation' }
TestMcpClientResources >> testListResourcesRejectsMalformedDefinition [
	"The client rejects a concrete resource with an invalid size."

	| definition page |

	self connectWithResourcesCapability.
	definition := self resourceDefinitionUri: 'test://resources/invalid' name: 'invalid'.
	definition at: 'size' put: -1.
	page := EsOrderedDictionary with: 'resources' -> (Array with: definition).
	transport enqueueResponse: page.
	self should: [client listResources] raise: Error
]

{ #category : 'Validation' }
TestMcpClientResources >> testListResourcesRejectsRepeatedCursor [
	"The client rejects a server that repeats a resource-list cursor."

	| firstPage secondPage |

	self connectWithResourcesCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'resources' put: #();
			at: 'nextCursor' put: 'same-cursor';
			yourself.
	secondPage :=
		EsOrderedDictionary new
			at: 'resources' put: #();
			at: 'nextCursor' put: 'same-cursor';
			yourself.
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	self should: [client listResources] raise: Error.
	self assert: transport requests size equals: 3
]

{ #category : 'Validation' }
TestMcpClientResources >> testListResourcesRequiresConnectedClient [
	"Resource listing is unavailable before initialization completes."

	self should: [client listResources] raise: Error.
	self assert: transport interactions isEmpty
]

{ #category : 'Validation' }
TestMcpClientResources >> testListResourcesRequiresResourcesCapability [
	"A connected client rejects listing without resources capability."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client listResources] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Copying' }
TestMcpClientResources >> testListResourcesReturnsDetachedDefinitions [
	"Listed definitions are detached from the transport response."

	| definition annotations page resources |

	self connectWithResourcesCapability.
	annotations := EsOrderedDictionary with: 'priority' -> 0.8.
	definition := self resourceDefinitionUri: 'test://resources/snapshot' name: 'snapshot'.
	definition at: 'annotations' put: annotations.
	page := EsOrderedDictionary with: 'resources' -> (Array with: definition).
	transport enqueueResponse: page.
	resources := client listResources.
	definition at: 'name' put: 'changed'.
	annotations at: 'priority' put: 0.1.
	self assert: (resources first at: 'name') equals: 'snapshot'.
	self assert: ((resources first at: 'annotations') at: 'priority') equals: 0.8
]

{ #category : 'Protocol Operations' }
TestMcpClientResources >> testMRTRResourceDriving [
	"Client drives multi-round-trip retry when readResource answers input_required."

	| inputRequired terminalResult result |

	self connectWithResourcesCapability.
	client elicitationCallback: [:req :c | EsOrderedDictionary with: 'action' -> 'accept' with: 'content' -> 'Access token'].
	inputRequired :=
		EsOrderedDictionary new
			at: 'resultType' put: 'input_required';
			at: 'requestState' put: 'state-resource-1';
			at: 'inputRequests'
				put: (
					EsOrderedDictionary with:
						'auth' -> (
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params'
									put: (EsOrderedDictionary with: 'prompt' -> 'Enter token');
								yourself));
			yourself.
	terminalResult := self textReadResultUri: 'test://resources/protected' text: 'Secret content'.
	transport enqueueResponse: inputRequired.
	transport enqueueResponse: terminalResult.

	result := client readResource: 'test://resources/protected'.

	self assert: result notNil.
	self assert: (((result at: 'contents') first) at: 'text') equals: 'Secret content'.
	self assert: transport requests size equals: 3.
	self
		assert: ((transport requests last at: 'params') at: 'requestState')
		equals: 'state-resource-1'.
	self
		assert: (((transport requests last at: 'params') at: 'inputResponses') at: 'auth')
		equals: (EsOrderedDictionary with: 'action' -> 'accept' with: 'content' -> 'Access token')
]

{ #category : 'Validation' }
TestMcpClientResources >> testMalformedResourcesCapabilityIsRejected [
	"A non-object resources capability cannot authorize operations."

	| capabilities |

	capabilities := EsOrderedDictionary with: 'resources' -> true.
	self connectWithCapabilities: capabilities.
	self should: [client listResources] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Validation' }
TestMcpClientResources >> testReadResourceRejectsMalformedResult [
	"The client rejects content containing both text and blob."

	| content result |

	self connectWithResourcesCapability.
	content :=
		EsOrderedDictionary new
			at: 'uri' put: 'test://resources/malformed';
			at: 'text' put: 'text';
			at: 'blob' put: 'blob';
			yourself.
	result := EsOrderedDictionary with: 'contents' -> (Array with: content).
	transport enqueueResponse: result.
	self should: [client readResource: 'test://resources/malformed'] raise: Error
]

{ #category : 'Validation' }
TestMcpClientResources >> testReadResourceRejectsRelativeUri [
	"A resource read requires an absolute URI before transport use."

	self connectWithResourcesCapability.
	self should: [client readResource: 'relative/path'] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Validation' }
TestMcpClientResources >> testReadResourceRequiresConnectedClient [
	"A resource read is unavailable before initialization completes."

	self should: [client readResource: 'test://resources/example'] raise: Error.
	self assert: transport interactions isEmpty
]

{ #category : 'Validation' }
TestMcpClientResources >> testReadResourceRequiresResourcesCapability [
	"A connected client rejects reads without resources capability."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client readResource: 'test://resources/example'] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Protocol Operations' }
TestMcpClientResources >> testReadResourceSendsExactRequestAndReturnsDetachedText [
	"Resource reads send the URI and return detached validated text."

	| scriptedResult result request parameters content |

	self connectWithResourcesCapability.
	scriptedResult := self textReadResultUri: 'test://resources/readme' text: 'Project documentation'.
	transport enqueueResponse: scriptedResult.
	result := client readResource: 'test://resources/readme'.
	((scriptedResult at: 'contents') first) at: 'text' put: 'changed'.
	request := transport requests last.
	self assert: (request at: 'jsonrpc') equals: '2.0'.
	self assert: (request at: 'id') equals: 2.
	self assert: (request at: 'method') equals: 'resources/read'.
	parameters := request at: 'params'.
	self assert: parameters size equals: 1.
	self assert: (parameters at: 'uri') equals: 'test://resources/readme'.
	content := (result at: 'contents') first.
	self assert: (content at: 'uri') equals: 'test://resources/readme'.
	self assert: (content at: 'mimeType') equals: 'text/markdown'.
	self assert: (content at: 'text') equals: 'Project documentation'
]

{ #category : 'Protocol Operations' }
TestMcpClientResources >> testReadResourceValidatesBinaryContent [
	"A resource read accepts one valid binary blob content object."

	| result content |

	self connectWithResourcesCapability.
	transport enqueueResponse:
		(self blobReadResultUri: 'test://images/logo' mimeType: 'image/png' blob: 'iVBORw0KGgo=').
	result := client readResource: 'test://images/logo'.
	content := (result at: 'contents') first.
	self assert: (content at: 'uri') equals: 'test://images/logo'.
	self assert: (content at: 'mimeType') equals: 'image/png'.
	self assert: (content at: 'blob') equals: 'iVBORw0KGgo='.
	self deny: (content includesKey: 'text')
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientResources >> textReadResultUri: uri text: text [
	"Answer a ReadResourceResult containing one text object."

	| content |

	content :=
		EsOrderedDictionary new
			at: 'uri' put: uri;
			at: 'mimeType' put: 'text/markdown';
			at: 'text' put: text;
			yourself.
	^EsOrderedDictionary with: 'contents' -> (Array with: content)
]
