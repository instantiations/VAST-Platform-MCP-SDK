"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpStdioClientTransport

`McpStdioClientTransport` connects an `McpClient` to an external MCP server running
as an operating system subprocess over standard input/output streams.

## Responsibilities

- Spawn and manage an OS subprocess using `OsProcessesApp` / `OsProcessStarter`.
- Maintain asynchronous I/O read loops for standard output and standard error.
- Correlate outbound JSON-RPC requests to incoming responses using semaphores
  and request timeouts.
- Forward server notifications and requests to `McpClient>>handleIncomingMessage:`.
- Cleanly terminate pending requests and reap process resources upon `close`.

## Lifecycle and boundaries

Owned by an `McpClient`. Spawns child process on connect and terminates it on close.
"
Class {
	#name : 'McpStdioClientTransport',
	#superclass : 'McpClientTransport',
	#instVars : [
		'command',
		'arguments',
		'environment',
		'workingDirectory',
		'runInShell',
		'process',
		'processMutex',
		'pendingRequests',
		'pendingRequestsMutex',
		'stdoutProcess',
		'stderrProcess',
		'stderrHandler',
		'stderrLines',
		'requestTimeout',
		'isClosing'
	],
	#category : 'McpApp'
}

{ #category : 'Instance Creation' }
McpStdioClientTransport class >> command: aCommandString [
	"Answer a new stdio transport configured with the given command and empty arguments.

	 Arguments:
		aCommandString - <String> executable name or path.
	 Answers:
		<McpStdioClientTransport>."

	^self command: aCommandString arguments: #()
]

{ #category : 'Instance Creation' }
McpStdioClientTransport class >> command: aCommandString arguments: aCollection [
	"Answer a new stdio transport configured with the given command and arguments.

	 Arguments:
		aCommandString - <String> executable name or path.
		aCollection - <SequenceableCollection> command-line arguments.
	 Answers:
		<McpStdioClientTransport>."

	^self new
		command: aCommandString;
		arguments: aCollection;
		yourself
]

{ #category : 'Instance Creation' }
McpStdioClientTransport class >> command: aCommandString
	arguments: aCollection
	environment: anEnvironment
	workingDirectory: aDirectory [
	"Answer a new stdio transport configured with command, arguments, environment, and working directory.

	 Arguments:
		aCommandString - <String> executable name or path.
		aCollection - <SequenceableCollection> command-line arguments.
		anEnvironment - <Dictionary> or nil.
		aDirectory - <String> or nil.
	 Answers:
		<McpStdioClientTransport>."

	^self new
		command: aCommandString;
		arguments: aCollection;
		environment: anEnvironment;
		workingDirectory: aDirectory;
		yourself
]

{ #category : 'Accessing' }
McpStdioClientTransport >> arguments [
	"Answer the configured sequence of command-line arguments.

	 Answers:
		<OrderedCollection of String>."

	^arguments copy
]

{ #category : 'Accessing' }
McpStdioClientTransport >> arguments: aCollection [
	"Set the command-line arguments to pass to the executable.

	 Arguments:
		aCollection - <SequenceableCollection> of arguments.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(aCollection isKindOf: SequenceableCollection)
		ifFalse: [self error: 'MCP stdio arguments must be a sequenceable collection'].
	arguments := aCollection asOrderedCollection collect: [:each | each asString].
	^self
]

{ #category : 'Starting and Stopping' }
McpStdioClientTransport >> close [
	"Terminate the subprocess gracefully, abort reader threads, and release pipe descriptors.

	 Answers:
		<McpStdioClientTransport> the receiver."

	| proc |

	processMutex critical: [
		isClosing := true.
		proc := process.
		process := nil].
	proc ifNotNil: [
		[proc inputStream ifNotNil: [:s | s close]] on: Error do: [:e | nil].
		(Delay forMilliseconds: 200) wait.
		proc isComplete
			ifFalse: [
				[proc terminate] on: Error do: [:e | nil].
				(Delay forMilliseconds: 500) wait.
				proc isComplete ifFalse: [[proc kill] on: Error do: [:e | nil]]].
		[proc closeStreams] on: Error do: [:e | nil]].
	stdoutProcess ifNotNil: [
		stdoutProcess terminate.
		stdoutProcess := nil].
	stderrProcess ifNotNil: [
		stderrProcess terminate.
		stderrProcess := nil].
	self terminatePendingRequestsWithReason: 'Transport closed'.
	^self
]

{ #category : 'Accessing' }
McpStdioClientTransport >> command [
	"Answer the configured executable name or path.

	 Answers:
		<String> or nil."

	^command
]

{ #category : 'Accessing' }
McpStdioClientTransport >> command: aString [
	"Set the executable name or path to execute.

	 Arguments:
		aString - <String> nonempty executable name or path.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'MCP stdio command must be a nonempty string'].
	command := aString.
	^self
]

{ #category : 'Connection Lifecycle' }
McpStdioClientTransport >> ensureConnected [
	"Ensure the subprocess is running, starting it lazily if not yet spawned.

	 Answers:
		<McpStdioClientTransport> the receiver."

	processMutex critical: [
		(process notNil and: [process isComplete not]) ifTrue: [^self].
		self startProcess].
	^self
]

{ #category : 'Accessing' }
McpStdioClientTransport >> environment [
	"Answer the optional environment variable overrides.

	 Answers:
		<Dictionary of String -> String> or nil."

	^environment ifNotNil: [:dict | dict copy]
]

{ #category : 'Accessing' }
McpStdioClientTransport >> environment: aDictionary [
	"Set environment variable overrides.

	 Arguments:
		aDictionary - <KeyedCollection> or nil.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP stdio environment must be a keyed collection or nil'].
	environment :=
		aDictionary ifNotNil: [:dict | | envDict |
			envDict := Dictionary new.
			dict keysAndValuesDo: [:k :v | envDict at: k asString put: v asString].
			envDict].
	^self
]

{ #category : 'Message Dispatching' }
McpStdioClientTransport >> handleIncomingJson: aDictionary [
	"Dispatch a decoded JSON-RPC message to pending requests or client handlers.

	 Arguments:
		aDictionary - <KeyedCollection> decoded JSON message.
	 Answers:
		<McpStdioClientTransport> the receiver."

	| id isResponse |

	(aDictionary isKindOf: KeyedCollection) ifFalse: [^self].
	(aDictionary at: 'jsonrpc' ifAbsent: [nil]) = '2.0' ifFalse: [^self].
	id := aDictionary at: 'id' ifAbsent: [nil].
	isResponse := (aDictionary includesKey: 'result') or: [aDictionary includesKey: 'error'].
	(isResponse and: [id notNil])
		ifTrue: [self resolvePendingRequest: id with: aDictionary]
		ifFalse: [self client ifNotNil: [:c | c handleIncomingMessage: aDictionary]].
	^self
]

{ #category : 'Connection Lifecycle',
  #vaVisibility : 'private' }
McpStdioClientTransport >> handleProcessTerminated [
	"Handle unexpected subprocess termination by failing outstanding requests.

	 Answers:
		<McpStdioClientTransport> the receiver."

	isClosing
		ifFalse: [self terminatePendingRequestsWithReason: 'Subprocess terminated unexpectedly'].
	^self
]

{ #category : 'IO Loops',
  #vaVisibility : 'private' }
McpStdioClientTransport >> handleStderrLine: aByteArray [
	"Record one stderr line into the circular buffer and notify the optional stderr handler.

	 Arguments:
		aByteArray - <ByteArray> or <String> raw line data.
	 Answers:
		<McpStdioClientTransport> the receiver."

	| lineString |

	aByteArray ifNil: [^self].
	lineString :=
		(aByteArray isKindOf: ByteArray)
			ifTrue: [(UnicodeString utf8: aByteArray repair: true) asString]
			ifFalse: [aByteArray asString].
	processMutex critical: [
		stderrLines addLast: lineString.
		stderrLines size > 100 ifTrue: [stderrLines removeFirst]].
	stderrHandler ifNotNil: [[stderrHandler value: lineString] on: Error do: [:handlerError | nil]].
	^self
]

{ #category : 'IO Loops' }
McpStdioClientTransport >> handleStdoutLine: aByteArray [
	"Decode and parse one line of stdout as a JSON-RPC message.

	 Arguments:
		aByteArray - <ByteArray> or <String> raw line data.
	 Answers:
		<McpStdioClientTransport> the receiver."

	| lineString json |

	aByteArray ifNil: [^self].
	lineString :=
		(aByteArray isKindOf: ByteArray)
			ifTrue: [(UnicodeString utf8: aByteArray repair: true) asString trimBlanks]
			ifFalse: [aByteArray asString trimBlanks].
	lineString isEmpty ifTrue: [^self].
	[json := McpJSONReader fromString: lineString] on: Error do: [:parseError | ^self].
	self handleIncomingJson: json.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpStdioClientTransport >> initialize [
	"Initialize stdio transport configuration and synchronization primitives.

	 Answers:
		<McpStdioClientTransport> the receiver."

	super initialize.
	arguments := OrderedCollection new.
	runInShell := false.
	requestTimeout := 60.
	pendingRequests := Dictionary new.
	pendingRequestsMutex := Semaphore forMutualExclusion.
	processMutex := Semaphore forMutualExclusion.
	stderrLines := OrderedCollection new.
	isClosing := false.
	^self
]

{ #category : 'Testing' }
McpStdioClientTransport >> isRunning [
	"Answer whether the subprocess is currently spawned and active.

	 Answers:
		<Boolean>."

	^process notNil and: [process isComplete not]
]

{ #category : 'Accessing' }
McpStdioClientTransport >> process [
	"Answer the underlying OS subprocess object.

	 Answers:
		<OsVastSubprocess> or nil."

	^process
]

{ #category : 'Accessing' }
McpStdioClientTransport >> requestTimeout [
	"Answer the timeout duration in seconds for awaiting JSON-RPC responses.

	 Answers:
		<Integer> seconds."

	^requestTimeout
]

{ #category : 'Accessing' }
McpStdioClientTransport >> requestTimeout: anInteger [
	"Set the timeout duration in seconds for awaiting JSON-RPC responses.

	 Arguments:
		anInteger - <Integer> positive timeout in seconds.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'MCP stdio request timeout must be a positive integer'].
	requestTimeout := anInteger.
	^self
]

{ #category : 'Message Dispatching' }
McpStdioClientTransport >> resolvePendingRequest: requestId with: aResponseDictionary [
	"Fulfill one pending request with its correlated response message.

	 Arguments:
		requestId - <String> or <Integer> request identifier.
		aResponseDictionary - <KeyedCollection> response message.
	 Answers:
		<McpStdioClientTransport> the receiver."

	pendingRequestsMutex critical: [
		pendingRequests
			at: requestId
			ifPresent: [:entry |
				entry at: #response put: aResponseDictionary.
				entry at: #completed put: true.
				(entry at: #semaphore) signal]].
	^self
]

{ #category : 'Accessing' }
McpStdioClientTransport >> runInShell [
	"Answer whether to spawn the process through the system command shell.

	 Answers:
		<Boolean>."

	^runInShell
]

{ #category : 'Accessing' }
McpStdioClientTransport >> runInShell: aBoolean [
	"Set whether to spawn the process through the system command shell.

	 Arguments:
		aBoolean - <Boolean> true to use shell, false otherwise.
	 Answers:
		<McpStdioClientTransport> the receiver."

	runInShell := aBoolean = true.
	^self
]

{ #category : 'IO Loops',
  #vaVisibility : 'private' }
McpStdioClientTransport >> runStderrLoop [
	"Continually read lines from subprocess errorStream and dispatch them to the stderr handler.

	 Answers:
		<McpStdioClientTransport> the receiver."

	| activeProc |

	activeProc := process.
	[
		[activeProc notNil and: [activeProc isComplete not or: [activeProc errorStream atEnd not]]]
			whileTrue: [| lineByteArray |
				lineByteArray :=
					[activeProc errorStream nextLine]
						on: Error
						do: [:readError |
							(Delay forMilliseconds: 50) wait.
							activeProc isComplete
								ifTrue: [readError return: nil]
								ifFalse: [readError pass]].
				lineByteArray ifNotNil: [self handleStderrLine: lineByteArray]]]
					ensure: [nil].
	^self
]

{ #category : 'IO Loops',
  #vaVisibility : 'private' }
McpStdioClientTransport >> runStdoutLoop [
	"Continually read newline-delimited JSON-RPC messages from subprocess stdout.

	 Answers:
		<McpStdioClientTransport> the receiver."

	| activeProc |

	activeProc := process.
	[
		[activeProc notNil and: [activeProc isComplete not or: [activeProc outputStream atEnd not]]]
			whileTrue: [| lineByteArray |
				lineByteArray :=
					[activeProc outputStream nextLine]
						on: Error
						do: [:readError |
							(Delay forMilliseconds: 50) wait.
							activeProc isComplete
								ifTrue: [readError return: nil]
								ifFalse: [readError pass]].
				lineByteArray ifNotNil: [self handleStdoutLine: lineByteArray]]]
					ensure: [self handleProcessTerminated].
	^self
]

{ #category : 'Sending' }
McpStdioClientTransport >> sendLine: aJsonString [
	"Write a newline-terminated UTF-8 JSON line to the subprocess standard input.

	 Arguments:
		aJsonString - <String> serialized JSON-RPC payload.
	 Answers:
		<McpStdioClientTransport> the receiver."

	| utf8Bytes |

	self ensureConnected.
	utf8Bytes := (aJsonString , (String with: Character lf)) asUtf8Bytes.
	processMutex critical: [
		(process isNil or: [process isComplete])
			ifTrue: [self error: 'MCP stdio process is not running'].
		process inputStream
			nextPutAll: utf8Bytes;
			flush].
	^self
]

{ #category : 'Protocol Operations' }
McpStdioClientTransport >> sendNotification: notificationDictionary [
	"Send one JSON-RPC notification to the subprocess without expecting a response.

	 Arguments:
		notificationDictionary - <KeyedCollection> JSON-RPC notification.
	 Answers:
		<McpStdioClientTransport> the receiver."

	| jsonString |

	(notificationDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP notification must be a keyed collection'].
	jsonString :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: notificationDictionary].
	self sendLine: jsonString.
	^self
]

{ #category : 'Protocol Operations' }
McpStdioClientTransport >> sendNotification: notificationDictionary headers: requestHeaders [
	"Send one JSON-RPC notification to the subprocess without transport headers.

	 Arguments:
		notificationDictionary - <KeyedCollection> JSON-RPC notification.
		requestHeaders - <KeyedCollection> transport headers, or nil.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(requestHeaders notNil and: [requestHeaders isEmpty not])
		ifTrue: [self error: 'MCP stdio transport does not support transport headers'].
	^self sendNotification: notificationDictionary
]

{ #category : 'Protocol Operations' }
McpStdioClientTransport >> sendRequest: requestDictionary id: requestId [
	"Send a JSON-RPC request to the subprocess standard input and await its correlated response.

	 Arguments:
		requestDictionary - <KeyedCollection> JSON-RPC request.
		requestId - <String> or <Integer> request identifier.
	 Answers:
		<Object> JSON-RPC result."

	| jsonString entry semaphore timerProcess response result |

	(requestDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP request must be a keyed collection'].
	(requestId isString or: [requestId isInteger])
		ifFalse: [self error: 'MCP request identifier is invalid'].
	jsonString :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: requestDictionary].
	semaphore := Semaphore new.
	entry := Dictionary new.
	entry
		at: #semaphore put: semaphore;
		at: #response put: nil;
		at: #completed put: false;
		at: #timedOut put: false;
		at: #errorReason put: nil.
	pendingRequestsMutex critical: [pendingRequests at: requestId put: entry].
	timerProcess :=
		[
			(Delay forSeconds: self requestTimeout) wait.
			pendingRequestsMutex critical: [
				pendingRequests
					at: requestId
					ifPresent: [:pending |
						(pending at: #completed)
							ifFalse: [
								pending at: #timedOut put: true.
								(pending at: #semaphore) signal]]]]
									forkAt: Processor userBackgroundPriority.
	[
		self sendLine: jsonString.
		semaphore wait.
		timerProcess terminate.
		(entry at: #timedOut) ifTrue: [self error: 'MCP request timed out: ' , requestId printString].
		(entry at: #errorReason) ifNotNil: [:reason | self error: reason].
		response := entry at: #response.
		response ifNil: [
			self error: 'MCP stdio request completed without a response: ' , requestId printString].
		result := self validatedResultFrom: response id: requestId.
		^result]
			ensure: [
				timerProcess terminate.
				pendingRequestsMutex critical: [pendingRequests removeKey: requestId ifAbsent: [nil]]]
]

{ #category : 'Protocol Operations' }
McpStdioClientTransport >> sendRequest: requestDictionary id: requestId headers: requestHeaders [
	"Send a JSON-RPC request with transport headers. Stdio transports reject headers.

	 Arguments:
		requestDictionary - <KeyedCollection> JSON-RPC request.
		requestId - <String> or <Integer> request identifier.
		requestHeaders - <KeyedCollection> transport headers, or nil.
	 Answers:
		<Object> JSON-RPC result."

	(requestHeaders notNil and: [requestHeaders isEmpty not])
		ifTrue: [self error: 'MCP stdio transport does not support transport headers'].
	^self sendRequest: requestDictionary id: requestId
]

{ #category : 'Connection Lifecycle' }
McpStdioClientTransport >> startProcess [
	"Spawn the configured OS subprocess and start the asynchronous reader threads.

	 Answers:
		<McpStdioClientTransport> the receiver."

	| starter progAndArgs |

	command ifNil: [self error: 'MCP stdio command is not configured'].
	isClosing := false.
	progAndArgs := (OrderedCollection with: command) , arguments.
	starter := OsProcessStarter command: progAndArgs.
	environment ifNotNil: [:env | env keysAndValuesDo: [:k :v | starter environment at: k put: v]].
	workingDirectory ifNotNil: [:cwd | starter workingDirectory: cwd].
	runInShell ifTrue: [starter runInShell: true].
	starter redirectIOToPipes.
	process := starter start.
	{ process inputStream. process outputStream. process errorStream }
		do: [:stream | stream isBytes: true].
	stdoutProcess := [self runStdoutLoop] forkAt: Processor userBackgroundPriority.
	stderrProcess := [self runStderrLoop] forkAt: Processor userBackgroundPriority.
	^self
]

{ #category : 'Accessing' }
McpStdioClientTransport >> stderrHandler [
	"Answer the optional block closure for receiving stderr output lines.

	 Answers:
		<BlockClosure> or nil."

	^stderrHandler
]

{ #category : 'Accessing' }
McpStdioClientTransport >> stderrHandler: aBlock [
	"Set the callback block closure for receiving stderr output lines.

	 Arguments:
		aBlock - <Block> one-argument block [:lineString | ...], or nil.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(aBlock isNil or: [aBlock isKindOf: Block])
		ifFalse: [self error: 'MCP stdio stderr handler must be a block or nil'].
	stderrHandler := aBlock.
	^self
]

{ #category : 'Accessing' }
McpStdioClientTransport >> stderrLines [
	"Answer a snapshot collection of captured stderr log lines.

	 Answers:
		<OrderedCollection of String>."

	processMutex critical: [^stderrLines copy]
]

{ #category : 'Testing' }
McpStdioClientTransport >> supportsRequestHeaders [
	"Answer whether the transport supports out-of-band request headers.

	 Stdio transports do not carry HTTP headers.

	 Answers:
		<Boolean> false."

	^false
]

{ #category : 'Connection Lifecycle',
  #vaVisibility : 'private' }
McpStdioClientTransport >> terminatePendingRequestsWithReason: aReasonString [
	"Signal all in-flight request semaphores with a termination failure reason.

	 Arguments:
		aReasonString - <String> error message.
	 Answers:
		<McpStdioClientTransport> the receiver."

	pendingRequestsMutex critical: [
		pendingRequests values do: [:entry |
			(entry at: #completed)
				ifFalse: [
					entry at: #errorReason put: aReasonString.
					(entry at: #semaphore) signal]].
		pendingRequests := Dictionary new].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStdioClientTransport >> validatedResultFrom: resultDictionary id: requestId [
	"Validate a JSON-RPC response and answer its result, signaling McpJsonRpcError on failure.

	 Arguments:
		resultDictionary - <KeyedCollection> decoded response.
		requestId - <String> or <Integer> expected identifier.
	 Answers:
		<Object> JSON-RPC result."

	| errorDictionary responseId |

	(resultDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid response: not a JSON object'].
	(resultDictionary at: 'jsonrpc' ifAbsent: [nil]) = '2.0'
		ifFalse: [self error: 'Invalid response: missing or incorrect jsonrpc version'].
	((resultDictionary includesKey: 'result') = (resultDictionary includesKey: 'error'))
		ifTrue: [self error: 'Invalid response: must contain exactly one of result or error'].
	responseId := resultDictionary at: 'id' ifAbsent: [nil].
	(resultDictionary includesKey: 'error')
		ifTrue: [
			(responseId notNil and: [responseId ~= requestId])
				ifTrue: [self error: 'Invalid response: ID mismatch'].
			errorDictionary := resultDictionary at: 'error'.
			(errorDictionary isKindOf: KeyedCollection)
				ifFalse: [self error: 'Invalid response: error is not an object'].
			(errorDictionary at: 'code' ifAbsent: [nil]) isInteger
				ifFalse: [self error: 'Invalid response: error code must be an integer'].
			(errorDictionary at: 'message' ifAbsent: [nil]) isString
				ifFalse: [self error: 'Invalid response: error message must be a string'].
			McpJsonRpcError
				signalCode: (errorDictionary at: 'code')
				message: (errorDictionary at: 'message')
				data: (errorDictionary at: 'data' ifAbsent: [nil])].
	responseId = requestId ifFalse: [self error: 'Invalid response: ID mismatch'].
	^resultDictionary at: 'result'
]

{ #category : 'Accessing' }
McpStdioClientTransport >> workingDirectory [
	"Answer the configured working directory path.

	 Answers:
		<String> or nil."

	^workingDirectory
]

{ #category : 'Accessing' }
McpStdioClientTransport >> workingDirectory: aString [
	"Set the working directory for the subprocess.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpStdioClientTransport> the receiver."

	(aString isNil or: [aString isString])
		ifFalse: [self error: 'MCP stdio working directory must be a string or nil'].
	workingDirectory := aString.
	^self
]
