"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpServerPrompts

`TestMcpServerPrompts` verifies the MCP server prompt protocol.

## Responsibilities

- Verify empty and cursor-paginated prompt listings without assuming order.
- Verify prompt rendering with validated string arguments.
- Verify unknown, missing, extraneous, and malformed arguments.
- Verify prompt-message validation and request-context propagation.

Each test creates a fresh server, dispatcher, and registry. Tests perform no
network I/O and create no background work.
"
Class {
	#name : 'TestMcpServerPrompts',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher',
		'registry'
	],
	#category : 'McpPromptTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> argumentNamed: argumentName required: required [
	"Answer one prompt argument definition."

	^EsOrderedDictionary new
		at: 'name' put: argumentName;
		at: 'required' put: required;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> assertErrorResponse: response code: expectedCode id: expectedIdentifier [
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
TestMcpServerPrompts >> assertSuccessfulResponse: response id: expectedIdentifier [
	"Assert the structural contract of a JSON-RPC result response."

	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier.
	self assert: (response includesKey: 'result').
	self deny: (response includesKey: 'error')
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> emptyResult [
	"Answer a valid empty GetPromptResult."

	^EsOrderedDictionary with: 'messages' -> #()
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> promptNamed: promptName arguments: argumentDefinitions block: renderingBlock [
	"Answer a configured block prompt."

	| prompt |

	prompt :=
		McpBlockPrompt new
			name: promptName;
			block: renderingBlock;
			yourself.
	argumentDefinitions ifNotNil: [prompt arguments: argumentDefinitions].
	^prompt
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> promptRequestNamed: promptName arguments: arguments id: identifier [
	"Answer a prompts/get request fixture."

	| parameters |

	parameters := EsOrderedDictionary with: 'name' -> promptName.
	arguments ifNotNil: [parameters at: 'arguments' put: arguments].
	^self requestMethod: 'prompts/get' params: parameters id: identifier
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> requestMethod: methodName params: parameters id: identifier [
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

{ #category : 'Initialization' }
TestMcpServerPrompts >> setUp [
	"Create a fresh server, registry, and dispatcher."

	super setUp.
	server := McpServer new.
	registry := server promptRegistry.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: server
]

{ #category : 'Protocol Operations' }
TestMcpServerPrompts >> testEmptyPromptListingReturnsCompleteResult [
	"An empty registry produces an empty list result without a cursor."

	| response result |

	response := dispatcher dispatch: (self requestMethod: 'prompts/list' params: nil id: 1).
	self assertSuccessfulResponse: response id: 1.
	result := response at: 'result'.
	self assert: result size equals: 1.
	self assert: (result at: 'prompts') isEmpty.
	self deny: (result includesKey: 'nextCursor')
]

{ #category : 'Dispatching' }
TestMcpServerPrompts >> testGetPromptPassesRequestContextToRenderer [
	"A renderer accepting context receives the dispatcher request context."

	| prompt requestContext capturedContext response |

	requestContext := McpServerRequestContext new.
	prompt :=
		self
			promptNamed: 'context.prompt'
			arguments: nil
			block: [:arguments :context |
				capturedContext := context.
				self textResult: 'context received'].
	registry registerPrompt: prompt.
	response :=
		dispatcher
			dispatch: (self promptRequestNamed: 'context.prompt' arguments: nil id: 2)
			context: requestContext.
	self assertSuccessfulResponse: response id: 2.
	self assert: capturedContext == requestContext
]

{ #category : 'Validation' }
TestMcpServerPrompts >> testGetPromptRejectsMalformedResult [
	"A malformed renderer result becomes an internal JSON-RPC error."

	| prompt malformedResult response |

	malformedResult :=
		EsOrderedDictionary
			with: 'messages' -> (Array with: (EsOrderedDictionary with: 'role' -> 'system')).
	prompt := self promptNamed: 'malformed.result' arguments: nil block: [malformedResult].
	registry registerPrompt: prompt.
	response :=
		dispatcher dispatch: (self promptRequestNamed: 'malformed.result' arguments: nil id: 3).
	self assertErrorResponse: response code: -32603 id: 3
]

{ #category : 'Validation' }
TestMcpServerPrompts >> testGetPromptRejectsMissingRequiredArgument [
	"A missing required argument is an invalid-params protocol error."

	| prompt callbackRan response |

	callbackRan := false.
	prompt :=
		self
			promptNamed: 'required.prompt'
			arguments: (Array with: (self argumentNamed: 'topic' required: true))
			block: [:arguments |
				callbackRan := true.
				self textResult: 'unused'].
	registry registerPrompt: prompt.
	response := dispatcher
		dispatch: (self promptRequestNamed: 'required.prompt' arguments: nil id: 4).
	self assertErrorResponse: response code: -32602 id: 4.
	self deny: callbackRan
]

{ #category : 'Validation' }
TestMcpServerPrompts >> testGetPromptRejectsNonStringArgumentValue [
	"Prompt argument values must be strings."

	| prompt arguments response |

	prompt :=
		self
			promptNamed: 'string.argument'
			arguments: (Array with: (self argumentNamed: 'topic' required: false))
			block: [:values | self textResult: 'unused'].
	registry registerPrompt: prompt.
	arguments := EsOrderedDictionary with: 'topic' -> 42.
	response :=
		dispatcher dispatch: (self promptRequestNamed: 'string.argument' arguments: arguments id: 5).
	self assertErrorResponse: response code: -32602 id: 5
]

{ #category : 'Validation' }
TestMcpServerPrompts >> testGetPromptRejectsUnknownArgument [
	"Arguments not declared by the prompt are rejected."

	| prompt arguments response |

	prompt :=
		self
			promptNamed: 'known.arguments'
			arguments: (Array with: (self argumentNamed: 'topic' required: false))
			block: [:values | self textResult: 'unused'].
	registry registerPrompt: prompt.
	arguments := EsOrderedDictionary with: 'extra' -> 'value'.
	response :=
		dispatcher dispatch: (self promptRequestNamed: 'known.arguments' arguments: arguments id: 6).
	self assertErrorResponse: response code: -32602 id: 6
]

{ #category : 'Error Handling' }
TestMcpServerPrompts >> testGetPromptRejectsUnknownPrompt [
	"An unknown prompt name produces an invalid-params protocol error."

	| response |

	response := dispatcher dispatch: (self promptRequestNamed: 'missing.prompt' arguments: nil id: 7).
	self assertErrorResponse: response code: -32602 id: 7.
	self assert: ((response at: 'error') at: 'message') equals: 'Unknown prompt: missing.prompt'
]

{ #category : 'Protocol Operations' }
TestMcpServerPrompts >> testGetPromptRendersValidatedArguments [
	"A prompt renderer receives detached values and returns valid messages."

	| prompt suppliedArguments capturedArguments response result message content |

	prompt :=
		self
			promptNamed: 'explain.topic'
			arguments: (Array with: (self argumentNamed: 'topic' required: true))
			block: [:arguments |
				capturedArguments := arguments.
				self textResult: 'Explain ' , (arguments at: 'topic')].
	registry registerPrompt: prompt.
	suppliedArguments := EsOrderedDictionary with: 'topic' -> 'Smalltalk'.
	response :=
		dispatcher
			dispatch: (self promptRequestNamed: 'explain.topic' arguments: suppliedArguments id: 8).
	suppliedArguments at: 'topic' put: 'changed'.
	self assertSuccessfulResponse: response id: 8.
	self assert: (capturedArguments at: 'topic') equals: 'Smalltalk'.
	result := response at: 'result'.
	message := (result at: 'messages') first.
	self assert: (message at: 'role') equals: 'user'.
	content := message at: 'content'.
	self assert: (content at: 'type') equals: 'text'.
	self assert: (content at: 'text') equals: 'Explain Smalltalk'
]

{ #category : 'Protocol Operations' }
TestMcpServerPrompts >> testOptionalPromptArgumentsMayBeOmitted [
	"A prompt with only optional arguments accepts an omitted argument object."

	| prompt response |

	prompt :=
		self
			promptNamed: 'optional.prompt'
			arguments: (Array with: (self argumentNamed: 'tone' required: false))
			block: [:arguments |
				self assert: arguments isEmpty.
				self textResult: 'default tone'].
	registry registerPrompt: prompt.
	response := dispatcher
		dispatch: (self promptRequestNamed: 'optional.prompt' arguments: nil id: 9).
	self assertSuccessfulResponse: response id: 9
]

{ #category : 'Protocol Operations' }
TestMcpServerPrompts >> testPromptListingPaginatesWithoutOrderAssumptions [
	"Cursor pagination returns every registered prompt exactly once."

	| firstResponse secondResponse firstResult secondResult firstPrompts secondPrompts names cursor
	  parameters |

	#('zeta.prompt' 'alpha.prompt' 'middle.prompt') do: [:promptName |
		registry
			registerPrompt: (self promptNamed: promptName arguments: nil block: [self emptyResult])].
	server listPageSize: 2.
	firstResponse := dispatcher dispatch: (self requestMethod: 'prompts/list' params: nil id: 10).
	self assertSuccessfulResponse: firstResponse id: 10.
	firstResult := firstResponse at: 'result'.
	firstPrompts := firstResult at: 'prompts'.
	self assert: firstPrompts size equals: 2.
	cursor := firstResult at: 'nextCursor'.
	parameters := EsOrderedDictionary with: 'cursor' -> cursor.
	secondResponse :=
		dispatcher dispatch: (self requestMethod: 'prompts/list' params: parameters id: 11).
	self assertSuccessfulResponse: secondResponse id: 11.
	secondResult := secondResponse at: 'result'.
	secondPrompts := secondResult at: 'prompts'.
	self assert: secondPrompts size equals: 1.
	self deny: (secondResult includesKey: 'nextCursor').
	names := Set new.
	firstPrompts do: [:definition | names add: (definition at: 'name')].
	secondPrompts do: [:definition | names add: (definition at: 'name')].
	self assert: names size equals: 3.
	self assert: (names includes: 'zeta.prompt').
	self assert: (names includes: 'alpha.prompt').
	self assert: (names includes: 'middle.prompt')
]

{ #category : 'Validation' }
TestMcpServerPrompts >> testPromptListingRejectsMalformedAndExpiredCursors [
	"Malformed and out-of-range prompt cursors are invalid parameters."

	| parameters response |

	#('not-a-cursor' '1') do: [:cursor |
		parameters := EsOrderedDictionary with: 'cursor' -> cursor.
		response :=
			dispatcher dispatch: (self requestMethod: 'prompts/list' params: parameters id: cursor).
		self assertErrorResponse: response code: -32602 id: cursor]
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerPrompts >> textResult: text [
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
