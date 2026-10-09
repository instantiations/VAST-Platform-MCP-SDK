"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpClientPrompts

`TestMcpClientPrompts` verifies client-side MCP prompt operations.

## Responsibilities

- Verify connection and negotiated-capability gating.
- Verify cursor pagination without assuming server ordering.
- Verify prompt definitions and argument declarations.
- Verify exact `prompts/get` request construction.
- Verify prompt-message validation and mutable-value isolation.

Each test creates a new client and `McpScriptedClientTransport`. Tests perform
no network I/O, create no background work, and make no timing assumptions.
"
Class {
	#name : 'TestMcpClientPrompts',
	#superclass : 'TestCase',
	#instVars : [
		'client',
		'transport'
	],
	#category : 'McpPromptTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientPrompts >> connectWithCapabilities: capabilities [
	"Connect using the supplied server capability declaration."

	transport enqueueResponse: (self initializeResultWith: capabilities).
	client connect
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientPrompts >> connectWithPromptsCapability [
	"Connect to a server advertising the prompts capability."

	self connectWithCapabilities: (EsOrderedDictionary with: 'prompts' -> EsOrderedDictionary new)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientPrompts >> initializeResultWith: capabilities [
	"Answer a valid initialization result with supplied capabilities."

	^EsOrderedDictionary new
		at: 'protocolVersion' put: '2025-11-25';
		at: 'capabilities' put: capabilities;
		at: 'serverInfo'
			put: (
				EsOrderedDictionary with: 'name' -> 'ScriptedPromptServer' with: 'version' -> '1.0.0');
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientPrompts >> promptDefinitionNamed: promptName [
	"Answer a minimally valid MCP prompt definition."

	^EsOrderedDictionary with: 'name' -> promptName
]

{ #category : 'Initialization' }
TestMcpClientPrompts >> setUp [
	"Create a fresh client and scripted transport."

	super setUp.
	transport := McpScriptedClientTransport new.
	client := McpClient new.
	client transport: transport
]

{ #category : 'Protocol Operations' }
TestMcpClientPrompts >> testGetPromptOmitsNilArguments [
	"A nil argument value omits the optional arguments member."

	| request parameters |

	self connectWithPromptsCapability.
	transport enqueueResponse: (self textPromptResult: 'Default prompt').
	client getPrompt: 'default.prompt' arguments: nil.
	request := transport requests last.
	self assert: (request at: 'method') equals: 'prompts/get'.
	parameters := request at: 'params'.
	self assert: parameters size equals: 1.
	self assert: (parameters at: 'name') equals: 'default.prompt'.
	self deny: (parameters includesKey: 'arguments')
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testGetPromptRejectsMalformedResult [
	"The client rejects a prompt result with an invalid message role."

	| content message result |

	self connectWithPromptsCapability.
	content :=
		EsOrderedDictionary new
			at: 'type' put: 'text';
			at: 'text' put: 'Invalid role';
			yourself.
	message :=
		EsOrderedDictionary new
			at: 'role' put: 'system';
			at: 'content' put: content;
			yourself.
	result := EsOrderedDictionary with: 'messages' -> (Array with: message).
	transport enqueueResponse: result.
	self should: [client getPrompt: 'invalid.result' arguments: nil] raise: Error
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testGetPromptRequiresConnectedClient [
	"Prompt retrieval is unavailable before initialization completes."

	self should: [client getPrompt: 'example.prompt' arguments: nil] raise: Error.
	self assert: transport interactions isEmpty
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testGetPromptRequiresPromptsCapability [
	"A connected client rejects retrieval when prompts were not advertised."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client getPrompt: 'example.prompt' arguments: nil] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Protocol Operations' }
TestMcpClientPrompts >> testGetPromptSendsDetachedArgumentsAndValidatesResult [
	"Prompt retrieval snapshots arguments and returns detached messages."

	| arguments scriptedResult result request parameters message content |

	self connectWithPromptsCapability.
	arguments := EsOrderedDictionary with: 'topic' -> 'Smalltalk'.
	scriptedResult := self textPromptResult: 'Explain Smalltalk'.
	transport enqueueResponse: scriptedResult.
	result := client getPrompt: 'explain.topic' arguments: arguments.
	arguments at: 'topic' put: 'changed'.
	((scriptedResult at: 'messages') first at: 'content') at: 'text' put: 'changed result'.
	request := transport requests last.
	self assert: (request at: 'jsonrpc') equals: '2.0'.
	self assert: (request at: 'id') equals: 2.
	self assert: (request at: 'method') equals: 'prompts/get'.
	parameters := request at: 'params'.
	self assert: (parameters at: 'name') equals: 'explain.topic'.
	self assert: ((parameters at: 'arguments') at: 'topic') equals: 'Smalltalk'.
	message := (result at: 'messages') first.
	self assert: (message at: 'role') equals: 'user'.
	content := message at: 'content'.
	self assert: (content at: 'type') equals: 'text'.
	self assert: (content at: 'text') equals: 'Explain Smalltalk'
]

{ #category : 'Protocol Operations' }
TestMcpClientPrompts >> testListPromptsCollectsEveryPageWithoutOrderAssumptions [
	"The client follows cursors and aggregates every prompt definition."

	| firstPage secondPage prompts names firstRequest secondRequest |

	self connectWithPromptsCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'prompts'
				put: (
					Array
						with: (self promptDefinitionNamed: 'zeta.prompt')
						with: (self promptDefinitionNamed: 'alpha.prompt'));
			at: 'nextCursor' put: 'page-2';
			yourself.
	secondPage :=
		EsOrderedDictionary
			with: 'prompts' -> (Array with: (self promptDefinitionNamed: 'middle.prompt')).
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	prompts := client listPrompts.
	self assert: prompts size equals: 3.
	names := Set new.
	prompts do: [:definition | names add: (definition at: 'name')].
	self assert: (names includes: 'zeta.prompt').
	self assert: (names includes: 'alpha.prompt').
	self assert: (names includes: 'middle.prompt').
	self assert: transport requests size equals: 3.
	firstRequest := transport requests at: 2.
	secondRequest := transport requests at: 3.
	self assert: (firstRequest at: 'id') equals: 2.
	self assert: (firstRequest at: 'method') equals: 'prompts/list'.
	self assert: (firstRequest at: 'params') isEmpty.
	self assert: (secondRequest at: 'id') equals: 3.
	self assert: (secondRequest at: 'method') equals: 'prompts/list'.
	self assert: ((secondRequest at: 'params') at: 'cursor') equals: 'page-2'
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testListPromptsRejectsDuplicateArgumentDefinitions [
	"The client rejects duplicate argument names in a listed prompt."

	| definition argument page |

	self connectWithPromptsCapability.
	argument := EsOrderedDictionary with: 'name' -> 'topic'.
	definition := self promptDefinitionNamed: 'duplicate.arguments'.
	definition at: 'arguments' put: (Array with: argument with: argument copy).
	page := EsOrderedDictionary with: 'prompts' -> (Array with: definition).
	transport enqueueResponse: page.
	self should: [client listPrompts] raise: Error
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testListPromptsRejectsMalformedDefinition [
	"The client rejects a listed prompt without a valid name."

	| invalidDefinition page |

	self connectWithPromptsCapability.
	invalidDefinition := EsOrderedDictionary with: 'name' -> ''.
	page := EsOrderedDictionary with: 'prompts' -> (Array with: invalidDefinition).
	transport enqueueResponse: page.
	self should: [client listPrompts] raise: Error
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testListPromptsRejectsRepeatedCursor [
	"The client rejects a server that repeats a prompt-list cursor."

	| firstPage secondPage |

	self connectWithPromptsCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'prompts' put: #();
			at: 'nextCursor' put: 'same-cursor';
			yourself.
	secondPage :=
		EsOrderedDictionary new
			at: 'prompts' put: #();
			at: 'nextCursor' put: 'same-cursor';
			yourself.
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	self should: [client listPrompts] raise: Error.
	self assert: transport requests size equals: 3
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testListPromptsRequiresPromptsCapability [
	"A connected client rejects listing when prompts were not advertised."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client listPrompts] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Copying' }
TestMcpClientPrompts >> testListPromptsReturnsDetachedDefinitions [
	"Listed definitions are detached from the transport response."

	| definition argument page prompts |

	self connectWithPromptsCapability.
	argument := EsOrderedDictionary with: 'name' -> 'topic'.
	definition := self promptDefinitionNamed: 'snapshot.prompt'.
	definition at: 'arguments' put: (Array with: argument).
	page := EsOrderedDictionary with: 'prompts' -> (Array with: definition).
	transport enqueueResponse: page.
	prompts := client listPrompts.
	definition at: 'name' put: 'changed.prompt'.
	argument at: 'name' put: 'changed'.
	self assert: (prompts first at: 'name') equals: 'snapshot.prompt'.
	self assert: ((prompts first at: 'arguments') first at: 'name') equals: 'topic'
]

{ #category : 'Protocol Operations' }
TestMcpClientPrompts >> testMRTRPromptDriving [
	"Client drives multi-round-trip retry when getPrompt answers input_required."

	| inputRequired terminalResult result |

	self connectWithPromptsCapability.
	client elicitationCallback: [:req :c | EsOrderedDictionary with: 'action' -> 'accept' with: 'content' -> 'User choice'].
	inputRequired :=
		EsOrderedDictionary new
			at: 'resultType' put: 'input_required';
			at: 'requestState' put: 'state-prompt-1';
			at: 'inputRequests'
				put: (
					EsOrderedDictionary with:
						'choice' -> (
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params'
									put: (EsOrderedDictionary with: 'prompt' -> 'Select mode');
								yourself));
			yourself.
	terminalResult := self textPromptResult: 'Final rendered prompt'.
	transport enqueueResponse: inputRequired.
	transport enqueueResponse: terminalResult.

	result := client getPrompt: 'test_prompt' arguments: nil.

	self assert: result notNil.
	self
		assert: (((result at: 'messages') first at: 'content') at: 'text')
		equals: 'Final rendered prompt'.
	self assert: transport requests size equals: 3.
	self assert: ((transport requests last at: 'params') at: 'requestState') equals: 'state-prompt-1'.
	self
		assert: (((transport requests last at: 'params') at: 'inputResponses') at: 'choice')
		equals: (EsOrderedDictionary with: 'action' -> 'accept' with: 'content' -> 'User choice')
]

{ #category : 'Validation' }
TestMcpClientPrompts >> testMalformedPromptsCapabilityIsRejected [
	"A non-object prompts capability cannot authorize prompt operations."

	| capabilities |

	capabilities := EsOrderedDictionary with: 'prompts' -> true.
	self connectWithCapabilities: capabilities.
	self should: [client listPrompts] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientPrompts >> textPromptResult: text [
	"Answer a GetPromptResult containing one user text message."

	| content message |

	content :=
		EsOrderedDictionary new
			at: 'type' put: 'text';
			at: 'text' put: text;
			yourself.
	message :=
		EsOrderedDictionary new
			at: 'role' put: 'user';
			at: 'content' put: content;
			yourself.
	^EsOrderedDictionary with: 'messages' -> (Array with: message)
]
