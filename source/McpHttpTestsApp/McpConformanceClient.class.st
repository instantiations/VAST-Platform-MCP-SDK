Class {
	#name : 'McpConformanceClient',
	#superclass : 'Object',
	#instVars : [
		'client',
		'serverUrl',
		'scenarioName',
		'protocolVersion',
		'context'
	],
	#category : 'McpHttpTestsApp'
}

{ #category : 'Instance Creation' }
McpConformanceClient class >> forUrl: aServerUrl scenario: aScenarioName [
	"Answer a new conformance client for aServerUrl and aScenarioName.

	 Arguments:
		aServerUrl - <String>.
		aScenarioName - <String>.
	 Answers:
		<McpConformanceClient>."

	^self new
		serverUrl: aServerUrl;
		scenarioName: aScenarioName;
		yourself
]

{ #category : 'Instance Creation' }
McpConformanceClient class >> forUrl: aServerUrl
	scenario: aScenarioName
	context: aDictionary
	protocolVersion: aVersionString [
	"Answer a fully configured conformance client instance.

	 Arguments:
		aServerUrl - <String>.
		aScenarioName - <String>.
		aDictionary - <KeyedCollection> or nil.
		aVersionString - <String> or nil.
	 Answers:
		<McpConformanceClient>."

	^self new
		serverUrl: aServerUrl;
		scenarioName: aScenarioName;
		context: aDictionary;
		protocolVersion: aVersionString;
		yourself
]

{ #category : 'Instance Creation' }
McpConformanceClient class >> new [
	"Answer a new initialized conformance test client.

	 Answers:
		<McpConformanceClient>."

	^super new initialize
]

{ #category : 'Execution' }
McpConformanceClient class >> runFromCommandLine: argumentArray [
	"Entry point for command-line / headless execution by the conformance test harness.
	 Accepts arguments where the last argument is the target server URL.
	 Reads MCP_CONFORMANCE_SCENARIO, MCP_CONFORMANCE_CONTEXT, and
	 MCP_CONFORMANCE_PROTOCOL_VERSION from OS environment variables.

	 Arguments:
		argumentArray - <SequenceableCollection of String>.
	 Answers:
		<Object> scenario run result."

	| url scenario rawContext context rawVersion client |

	argumentArray isEmpty ifTrue: [self error: 'Missing target server URL argument'].
	url := argumentArray last.
	scenario := OsProcessEnvironment current at: 'MCP_CONFORMANCE_SCENARIO' ifAbsent: [nil].
	scenario ifNil: [self error: 'MCP_CONFORMANCE_SCENARIO environment variable not set'].
	rawContext := OsProcessEnvironment current at: 'MCP_CONFORMANCE_CONTEXT' ifAbsent: [nil].
	context :=
		(rawContext notNil and: [rawContext notEmpty])
			ifTrue: [
				[McpJSONReader fromString: rawContext]
					on: Error
					do: [:e | EsOrderedDictionary new]]
			ifFalse: [EsOrderedDictionary new].
	rawVersion :=
		OsProcessEnvironment current at: 'MCP_CONFORMANCE_PROTOCOL_VERSION' ifAbsent: [nil].

	client :=
		self
			forUrl: url
			scenario: scenario
			context: context
			protocolVersion: rawVersion.
	^client run
]

{ #category : 'Execution' }
McpConformanceClient class >> runScenario: aScenarioName onUrl: aServerUrl [
	"Run a single named conformance scenario against an MCP server URL.

	 Arguments:
		aScenarioName - <String>.
		aServerUrl - <String>.
	 Answers:
		<Object> scenario run result."

	^(self forUrl: aServerUrl scenario: aScenarioName) run
]

{ #category : 'Accessing' }
McpConformanceClient >> context [
	"Answer the scenario context dictionary.

	 Answers:
		<KeyedCollection>."

	^context ifNil: [context := EsOrderedDictionary new]
]

{ #category : 'Accessing' }
McpConformanceClient >> context: aDictionary [
	"Set the scenario context dictionary.

	 Arguments:
		aDictionary - <KeyedCollection> or nil.
	 Answers:
		<McpConformanceClient> the receiver."

	context := aDictionary ifNil: [EsOrderedDictionary new].
	^self
]

{ #category : 'Initialization' }
McpConformanceClient >> initialize [
	"Initialize conformance client defaults.

	 Answers:
		<McpConformanceClient> the receiver."

	super initialize.
	context := EsOrderedDictionary new.
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpConformanceClient >> newClient [
	"Answer a new McpClient configured for the target server URL and mode.

	 Answers:
		<McpClient>."

	| c mode |

	mode :=
		(self protocolVersion notNil and: [McpProtocolVersion isModern: self protocolVersion])
			ifTrue: [#modern]
			ifFalse: [#auto].
	c := McpClient new.
	c mode: mode.
	c transport: (McpHttpClientTransport url: self serverUrl).
	^c
]

{ #category : 'Accessing' }
McpConformanceClient >> protocolVersion [
	"Answer the requested protocol version override, or nil.

	 Answers:
		<String> or nil."

	^protocolVersion
]

{ #category : 'Accessing' }
McpConformanceClient >> protocolVersion: aString [
	"Set the protocol version override.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpConformanceClient> the receiver."

	protocolVersion := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Execution' }
McpConformanceClient >> run [
	"Dispatch execution to the matching conformance scenario handler.

	 Answers:
		<Object> scenario outcome."

	| name |

	name := self scenarioName ifNil: ['initialize'].
	(name = 'initialize' or: [name = 'tools_call' or: [name = 'tools-call']])
		ifTrue: [^self runBasicScenario].
	name = 'json-schema-ref-no-deref' ifTrue: [^self runListToolsOnlyScenario].
	name = 'json-schema-2020-12-preservation'
		ifTrue: [^self runJsonSchemaPreservationScenario].
	name = 'request-metadata' ifTrue: [^self runRequestMetadataScenario].
	name = 'sep-2322-client-request-state' ifTrue: [^self runMrtrClientScenario].
	name = 'elicitation-defaults' ifTrue: [^self runElicitationDefaultsScenario].
	self error: 'Unknown conformance scenario: ' , name
]

{ #category : 'Scenarios' }
McpConformanceClient >> runBasicScenario [
	"Execute the basic initialize and tools/call scenario."

	| c tools tool |

	c := self newClient.
	[
		c connect.
		tools := c listTools.
		tools notEmpty
			ifTrue: [
				tool := tools first.
				c
					callTool: (tool at: 'name')
					arguments: (EsOrderedDictionary with: 'a' -> 2 with: 'b' -> 3)].
		^tools]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runElicitationDefaultsScenario [
	"Execute elicitation-defaults: configure elicitation callback and call trigger tool."

	| c |

	c := self newClient.
	c elicitationCallback: [:inputReq :clientRef |
		EsOrderedDictionary
			with: 'action' -> 'accept'
			with: 'content' -> EsOrderedDictionary new].
	[
		c connect.
		c listTools.
		^c callTool: 'test_client_elicitation_defaults' arguments: EsOrderedDictionary new]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runJsonSchemaPreservationScenario [
	"Execute json-schema-2020-12-preservation: list tools, locate focal tool, and echo schema."

	| c tools focalTool |

	c := self newClient.
	[
		c connect.
		tools := c listTools.
		focalTool :=
			tools
				detect: [:t | (t at: 'name' ifAbsent: ['']) = 'json_schema_2020_12_tool']
				ifNone: [self error: 'Focal tool json_schema_2020_12_tool not advertised'].
		^c
			callTool: 'json_schema_echo'
			arguments: (EsOrderedDictionary with: 'schema' -> (focalTool at: 'inputSchema'))]
				ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runListToolsOnlyScenario [
	"Execute the json-schema-ref-no-deref scenario: list tools without fetching network $ref."

	| c |

	c := self newClient.
	[
		c connect.
		^c listTools]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runMrtrClientScenario [
	"Execute sep-2322-client-request-state: test MRTR retry loop and state isolation."

	| c r1 r1Type reqs state responses r2 r2Type r3 |

	c := self newClient.
	[
		c connect.
		c listTools.

		r1 := c callTool: 'test_mrtr_echo_state' arguments: EsOrderedDictionary new.
		r1Type :=
			(r1 isKindOf: KeyedCollection)
				ifTrue: [r1 at: 'resultType' ifAbsent: [nil]]
				ifFalse: [nil].
		(r1Type = 'input_required' or: [r1Type = 'inputRequired'])
			ifTrue: [
				reqs := r1 at: 'inputRequests' ifAbsent: [EsOrderedDictionary new].
				state := r1 at: 'requestState' ifAbsent: [nil].
				responses := EsOrderedDictionary new.
				reqs keysAndValuesDo: [:k :req |
					responses
						at: k
						put: (
							EsOrderedDictionary
								with: 'action' -> 'accept'
								with: 'content' -> (EsOrderedDictionary with: 'confirmed' -> true))].
				[c callTool: 'test_mrtr_unrelated' arguments: EsOrderedDictionary new]
					on: Error
					do: [:e | nil].
				c
					callTool: 'test_mrtr_echo_state'
					arguments: (
						EsOrderedDictionary new
							at: 'inputResponses' put: responses;
							at: 'requestState' put: state;
							yourself)].

		r2 := c callTool: 'test_mrtr_no_state' arguments: EsOrderedDictionary new.
		r2Type :=
			(r2 isKindOf: KeyedCollection)
				ifTrue: [r2 at: 'resultType' ifAbsent: [nil]]
				ifFalse: [nil].
		(r2Type = 'input_required' or: [r2Type = 'inputRequired'])
			ifTrue: [
				reqs := r2 at: 'inputRequests' ifAbsent: [EsOrderedDictionary new].
				responses := EsOrderedDictionary new.
				reqs keysAndValuesDo: [:k :req |
					responses
						at: k
						put: (
							EsOrderedDictionary
								with: 'action' -> 'accept'
								with: 'content' -> (EsOrderedDictionary with: 'confirmed' -> true))].
				c
					callTool: 'test_mrtr_no_state'
					arguments: (EsOrderedDictionary with: 'inputResponses' -> responses)].

		r3 := c callTool: 'test_mrtr_no_result_type' arguments: EsOrderedDictionary new.
		^r3]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runRequestMetadataScenario [
	"Execute request-metadata scenario: discover server and list tools using modern sessionless requests."

	| c |

	c := McpClient modern.
	c transport: (McpHttpClientTransport url: self serverUrl).
	[
		c connect.
		^c listTools]
			ensure: [c close]
]

{ #category : 'Accessing' }
McpConformanceClient >> scenarioName [
	"Answer the scenario to execute.

	 Answers:
		<String>."

	^scenarioName
]

{ #category : 'Accessing' }
McpConformanceClient >> scenarioName: aString [
	"Set the scenario to execute.

	 Arguments:
		aString - <String>.
	 Answers:
		<McpConformanceClient> the receiver."

	scenarioName := aString copy.
	^self
]

{ #category : 'Accessing' }
McpConformanceClient >> serverUrl [
	"Answer the target server URL.

	 Answers:
		<String>."

	^serverUrl
]

{ #category : 'Accessing' }
McpConformanceClient >> serverUrl: aString [
	"Set the target server URL.

	 Arguments:
		aString - <String>.
	 Answers:
		<McpConformanceClient> the receiver."

	serverUrl := aString copy.
	^self
]
