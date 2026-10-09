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

{ #category : 'Execution' }
McpConformanceClient class >> main [
	"Headless entry point invoked from an execution script or command line.
	 Runs the requested scenario and terminates the VM process with exit code 0 on success
	 or 1 on failure."

	[
		self runFromCommandLine: System commandLine.
		System exit: 0 withObject: nil]
			on: Error
			do: [:ex |
				Transcript show: 'Conformance client failed: ' , ex messageText; cr.
				System exit: 1 withObject: nil]
]

{ #category : 'Instance Creation' }
McpConformanceClient class >> new [
	"Answer a new initialized conformance test client.

	 Answers:
		<McpConformanceClient>."

	^super new initialize
]

{ #category : 'Execution' }
McpConformanceClient class >> run [
	"VAST Packager startup entry point.
	 Executed automatically when the image starts up with this class as startUpClass."

	self main
]

{ #category : 'Execution' }
McpConformanceClient class >> runAllOnUrl: aServerUrl [
	"Run all client scenarios in sequence against aServerUrl and report a formatted summary to the Transcript.

	 Arguments:
		aServerUrl - <String>.
	 Answers:
		<KeyedCollection> dictionary mapping scenario names to outcomes."

	| scenarios results passedCount |

	scenarios := #(
		'initialize'
		'tools-call'
		'request-metadata'
		'sep-2322-client-request-state'
		'elicitation-defaults'
		'json-schema-2020-12-preservation').

	results := EsOrderedDictionary new.
	passedCount := 0.

	Transcript
		cr;
		show: '=======================================================';
		cr;
		show: 'Running MCP Client Conformance Suite against: ' , aServerUrl;
		cr;
		show: '=======================================================';
		cr.

	scenarios do: [:scenarioName |
		[
			(self forUrl: aServerUrl scenario: scenarioName) run.
			results at: scenarioName put: 'PASSED'.
			passedCount := passedCount + 1.
			Transcript
				show: '  [PASS] ' , scenarioName;
				cr]
					on: Error
					do: [:ex |
						results at: scenarioName put: ('FAILED: ' , ex messageText).
						Transcript
							show: '  [FAIL] ' , scenarioName , ' -> ' , ex messageText;
							cr]].

	Transcript
		show: '-------------------------------------------------------';
		cr;
		show: 'Results: ' , passedCount printString , '/' , scenarios size printString , ' scenarios passed.';
		cr;
		show: '=======================================================';
		cr.

	^results
]

{ #category : 'Execution' }
McpConformanceClient class >> runFromCommandLine: argumentArray [
	"Entry point for command-line / headless execution by the conformance test harness.
	 Accepts arguments where the last argument is the target server URL.
	 Reads MCP_CONFORMANCE_SCENARIO, MCP_CONFORMANCE_CONTEXT, and
	 MCP_CONFORMANCE_PROTOCOL_VERSION from OS environment variables, or
	 falls back to positional argument for scenario.

	 Arguments:
		argumentArray - <SequenceableCollection of String>.
	 Answers:
		<Object> scenario run result."

	| url scenario rawContext context rawVersion client |

	argumentArray isEmpty ifTrue: [self error: 'Missing target server URL argument'].
	url := argumentArray last.
	scenario := OsProcessEnvironment current at: 'MCP_CONFORMANCE_SCENARIO' ifAbsent: [nil].
	(scenario isNil or: [scenario isEmpty])
		ifTrue: [argumentArray size >= 2 ifTrue: [scenario := argumentArray first]].
	scenario ifNil: [self error: 'MCP_CONFORMANCE_SCENARIO not specified'].
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

{ #category : 'Logging',
  #vaVisibility : 'private' }
McpConformanceClient >> log: aMessage [
	"Output a diagnostic message to the Transcript."

	Transcript
		show: '[McpConformanceClient] ' , aMessage;
		cr
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
	"Dispatch execution to the matching conformance scenario handler with logging and error reporting.

	 Answers:
		<KeyedCollection> scenario outcome dictionary."

	| name result |

	name := self scenarioName ifNil: ['initialize'].
	self log: 'Starting scenario: ' , name , ' against: ' , self serverUrl.
	[
		(name = 'initialize' or: [name = 'tools_call' or: [name = 'tools-call']])
			ifTrue: [result := self runBasicScenario].
		name = 'json-schema-ref-no-deref'
			ifTrue: [result := self runListToolsOnlyScenario].
		name = 'json-schema-2020-12-preservation'
			ifTrue: [result := self runJsonSchemaPreservationScenario].
		name = 'request-metadata'
			ifTrue: [result := self runRequestMetadataScenario].
		name = 'sep-2322-client-request-state'
			ifTrue: [result := self runMrtrClientScenario].
		(name = 'elicitation-defaults'
			or: [name = 'elicitation-sep1034-client-defaults'])
				ifTrue: [result := self runElicitationDefaultsScenario].
		((name indexOfSubCollection: 'auth/' startingAt: 1) = 1)
			ifTrue: [result := self runAuthScenario: name].
		result ifNil: [self error: 'Unknown conformance scenario: ' , name].
		self log: 'Scenario ' , name , ' COMPLETED successfully.'.
		^result]
			on: Error
			do: [:ex |
				self log: 'Scenario ' , name , ' FAILED: ' , ex messageText.
				ex pass]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runBasicScenario [
	"Execute the basic initialize and tools/call scenario."

	| c tools tool toolName props args toolResult resultDict |

	c := self newClient.
	[
		self log: 'Connecting to ' , self serverUrl.
		c connect.
		self log: 'Connected. Protocol version: ' , c protocolVersion printString.

		tools := c listTools.
		self log: 'Discovered ' , tools size printString , ' tools.'.
		toolResult := nil.
		tools notEmpty
			ifTrue: [
				tool :=
					tools
						detect: [:t | | p |
							p :=
								(t at: 'inputSchema' ifAbsent: [EsOrderedDictionary new])
									at: 'properties'
									ifAbsent: [EsOrderedDictionary new].
							p includesKey: 'a']
						ifNone: [tools first].
				toolName := tool at: 'name'.
				props :=
					(tool at: 'inputSchema' ifAbsent: [EsOrderedDictionary new])
						at: 'properties'
						ifAbsent: [EsOrderedDictionary new].
				args :=
					(props includesKey: 'a')
						ifTrue: [EsOrderedDictionary with: 'a' -> 2 with: 'b' -> 3]
						ifFalse: [EsOrderedDictionary new].
				self
					log: 'Calling tool: ' , toolName , ' with arguments: ' , args printString.
				toolResult := c callTool: toolName arguments: args.
				self log: 'Tool call result: ' , toolResult printString].

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: self scenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'protocolVersion' put: c protocolVersion;
				at: 'toolCount' put: tools size;
				at: 'toolResult' put: toolResult;
				yourself.
		^resultDict]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runElicitationDefaultsScenario [
	"Execute elicitation-defaults: configure elicitation callback and call trigger tool."

	| c result resultDict |

	c := self newClient.
	c elicitationCallback: [:inputReq :clientRef |
		self log: 'Received elicitation request; providing accept response.'.
		EsOrderedDictionary
			with: 'action' -> 'accept'
			with: 'content' -> EsOrderedDictionary new].
	[
		self log: 'Connecting to ' , self serverUrl.
		c connect.
		c listTools.
		self log: 'Calling trigger tool test_client_elicitation_defaults'.
		result :=
			c
				callTool: 'test_client_elicitation_defaults'
				arguments: EsOrderedDictionary new.
		self log: 'Elicitation trigger result: ' , result printString.

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: self scenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'result' put: result;
				yourself.
		^resultDict]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runJsonSchemaPreservationScenario [
	"Execute json-schema-2020-12-preservation: list tools, locate focal tool, and echo schema."

	| c tools focalTool echoResult resultDict |

	c := self newClient.
	[
		self log: 'Connecting to ' , self serverUrl.
		c connect.
		tools := c listTools.
		focalTool :=
			tools
				detect: [:t | (t at: 'name' ifAbsent: ['']) = 'json_schema_2020_12_tool']
				ifNone: [self error: 'Focal tool json_schema_2020_12_tool not advertised'].
		self log: 'Found focal tool json_schema_2020_12_tool. Echoing schema...'.
		echoResult :=
			c
				callTool: 'json_schema_echo'
				arguments:
					(EsOrderedDictionary with: 'schema' -> (focalTool at: 'inputSchema')).
		self log: 'Echo result: ' , echoResult printString.

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: self scenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'echoResult' put: echoResult;
				yourself.
		^resultDict]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runListToolsOnlyScenario [
	"Execute the json-schema-ref-no-deref scenario: list tools without fetching network $ref."

	| c tools resultDict |

	c := self newClient.
	[
		self log: 'Connecting to ' , self serverUrl.
		c connect.
		self log: 'Connected. Protocol version: ' , c protocolVersion printString.
		tools := c listTools.
		self
			log:
				'Listed ' , tools size printString ,
					' tools without fetching network $ref.'.

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: self scenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'protocolVersion' put: c protocolVersion;
				at: 'tools' put: tools;
				yourself.
		^resultDict]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runMrtrClientScenario [
	"Execute sep-2322-client-request-state: test MRTR retry loop and state isolation."

	| c tools r1 r2 r3 resultDict |

	c := self newClient.
	c elicitationCallback: [:inputReq :clientRef |
		EsOrderedDictionary
			with: 'action' -> 'accept'
			with: 'content' -> (EsOrderedDictionary with: 'confirmed' -> true)].
	[
		self log: 'Connecting to ' , self serverUrl.
		c connect.
		tools := c listTools.
		self log: 'Discovered ' , tools size printString , ' tools.'.

		self log: 'Step 1: Calling test_mrtr_echo_state (MRTR round-trip with requestState).'.
		r1 := c callTool: 'test_mrtr_echo_state' arguments: EsOrderedDictionary new.
		self log: 'Step 1 result: ' , r1 printString.

		self log: 'Step 2: Calling test_mrtr_unrelated for state isolation check.'.
		c callTool: 'test_mrtr_unrelated' arguments: EsOrderedDictionary new.

		self log: 'Step 3: Calling test_mrtr_no_state (MRTR round-trip without requestState).'.
		r2 := c callTool: 'test_mrtr_no_state' arguments: EsOrderedDictionary new.
		self log: 'Step 3 result: ' , r2 printString.

		self log: 'Step 4: Calling test_mrtr_no_result_type (must assume complete by default).'.
		r3 := c callTool: 'test_mrtr_no_result_type' arguments: EsOrderedDictionary new.
		self log: 'Step 4 result: ' , r3 printString.

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: self scenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'finalResult' put: r3;
				yourself.
		^resultDict]
			ensure: [c close]
]

{ #category : 'Scenarios' }
McpConformanceClient >> runRequestMetadataScenario [
	"Execute request-metadata scenario: discover server and list tools using modern sessionless requests."

	| c tools resultDict |

	c := McpClient modern.
	c transport: (McpHttpClientTransport url: self serverUrl).
	[
		self log: 'Connecting modern client to ' , self serverUrl.
		c connect.
		self
			log:
				'Connected in modern mode. Discovered server: ' ,
					(c serverInfo at: 'name' ifAbsent: ['server']).
		tools := c listTools.
		self
			log:
				'Listed ' , tools size printString ,
					' tools with per-request _meta envelope.'.

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: self scenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'protocolVersion' put: c protocolVersion;
				at: 'tools' put: tools;
				yourself.
		^resultDict]
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
