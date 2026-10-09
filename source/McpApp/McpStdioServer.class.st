"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpStdioServer

`McpStdioServer` hosts an in-process `McpServer` over standard input and
output, servicing JSON-RPC requests from desktop hosts (Claude Desktop,
Cursor, CLion) according to the MCP stdio transport specification.

## Responsibilities

- Read line-delimited JSON-RPC requests from standard input via CFS/TTY streams.
- Dispatch requests to `McpJsonRpcDispatcher` under modern `2026-07-28` context.
- Write newline-delimited JSON-RPC responses to standard output.
- Guard standard output from log corruption by directing internal logs to
  standard error.

## Lifecycle and boundaries

A host process launches the Smalltalk image with stdio redirection.
`McpStdioServer` runs until standard input reaches end-of-file or until
`stop` is sent.
"
Class {
	#name : 'McpStdioServer',
	#superclass : 'Object',
	#instVars : [
		'server',
		'dispatcher',
		'isRunning',
		'inputStream',
		'outputStream',
		'process',
		'negotiatedProtocolVersion'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpApp'
}

{ #category : 'Instance Creation' }
McpStdioServer class >> forServer: anMcpServer [
	"Answer a new stdio server hosting anMcpServer.

	 Arguments:
		anMcpServer - <McpServer>.
	 Answers:
		<McpStdioServer>."

	^self new server: anMcpServer
]

{ #category : 'Instance Creation' }
McpStdioServer class >> new [
	"Answer a new initialized stdio server.

	 Answers:
		<McpStdioServer>."

	^super new initialize
]

{ #category : 'Accessing' }
McpStdioServer >> dispatcher [
	"Answer the protocol dispatcher, creating a default one if needed.

	 Answers:
		<McpJsonRpcDispatcher>."

	dispatcher ifNil: [
		self server ifNotNil: [:s |
			dispatcher :=
				McpJsonRpcDispatcher new
					server: s;
					yourself]].
	^dispatcher
]

{ #category : 'Accessing' }
McpStdioServer >> dispatcher: aDispatcher [
	"Set the protocol dispatcher.

	 Arguments:
		aDispatcher - <McpJsonRpcDispatcher>.
	 Answers:
		<McpStdioServer> the receiver."

	dispatcher := aDispatcher.
	^self
]

{ #category : 'accessing',
  #vaVisibility : 'private' }
McpStdioServer >> extractMetaParametersFrom: params into: context [
	"Extract client info, capabilities, and log level from _meta parameters into the request context.

	 Arguments:
		params - <KeyedCollection> or nil.
		context - <McpServerRequestContext>."

	| meta |

	(params isKindOf: KeyedCollection) ifFalse: [^self].
	meta := params at: '_meta' ifAbsent: [nil].
	(meta isKindOf: KeyedCollection) ifFalse: [^self].

	(meta at: 'io.modelcontextprotocol/clientInfo' ifAbsent: [nil])
		ifNotNil: [:info | context clientInfo: info].
	(meta at: 'io.modelcontextprotocol/clientCapabilities' ifAbsent: [nil])
		ifNotNil: [:caps | context clientCapabilities: caps].
	(meta at: 'io.modelcontextprotocol/logLevel' ifAbsent: [nil])
		ifNotNil: [:lvl | context logLevel: lvl].
	^self
]

{ #category : 'accessing',
  #vaVisibility : 'private' }
McpStdioServer >> extractProtocolVersionFrom: method params: params [
	"Extract the protocol version from the JSON-RPC request.

	 Arguments:
		method - <String> or nil.
		params - <KeyedCollection> or nil.
	 Answers:
		<String>"

	| reqVersion meta |

	reqVersion := nil.
	(params isKindOf: KeyedCollection)
		ifTrue: [
			meta := params at: '_meta' ifAbsent: [nil].
			(meta isKindOf: KeyedCollection)
				ifTrue: [
					reqVersion := meta at: 'io.modelcontextprotocol/protocolVersion' ifAbsent: [nil]]].
	method = 'initialize'
		ifTrue: [
			(params isKindOf: KeyedCollection)
				ifTrue: [reqVersion := params at: 'protocolVersion' ifAbsent: [nil]]].
	reqVersion ifNil: [
		reqVersion := self negotiatedProtocolVersion ifNil: ['2026-07-28']].
	^reqVersion
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpStdioServer >> initialize [
	"Initialize stdio server state.

	 Answers:
		<McpStdioServer> the receiver."

	super initialize.
	isRunning := false.
	negotiatedProtocolVersion := nil.
	^self
]

{ #category : 'Accessing' }
McpStdioServer >> inputStream [
	"Answer the input stream.

	 Answers:
		<Stream>."

	^inputStream
]

{ #category : 'Accessing' }
McpStdioServer >> inputStream: aStream [
	"Set the input stream from which JSON-RPC requests are read.

	 Arguments:
		aStream - <Stream>.
	 Answers:
		<McpStdioServer> the receiver."

	inputStream := aStream.
	^self
]

{ #category : 'Testing' }
McpStdioServer >> isRunning [
	"Answer whether the server is currently running.

	 Answers:
		<Boolean>."

	^isRunning == true
]

{ #category : 'Accessing' }
McpStdioServer >> negotiatedProtocolVersion [
	"Answer the protocol version negotiated via initialize handshake, or nil.

	 Answers:
		<String> or nil."

	^negotiatedProtocolVersion
]

{ #category : 'Accessing' }
McpStdioServer >> negotiatedProtocolVersion: aString [
	"Set the protocol version negotiated via initialize handshake.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpStdioServer> the receiver."

	negotiatedProtocolVersion := aString.
	^self
]

{ #category : 'Accessing' }
McpStdioServer >> outputStream [
	"Answer the output stream.

	 Answers:
		<Stream>."

	^outputStream
]

{ #category : 'Accessing' }
McpStdioServer >> outputStream: aStream [
	"Set the output stream to which JSON-RPC responses are written.

	 Arguments:
		aStream - <Stream>.
	 Answers:
		<McpStdioServer> the receiver."

	outputStream := aStream.
	^self
]

{ #category : 'Protocol Operations' }
McpStdioServer >> processMessage: aLine [
	"Parse, dispatch, and format one JSON-RPC message over standard output.

	 Arguments:
		aLine - <String> or <ByteArray> line from standard input.
	 Answers:
		<McpStdioServer> the receiver."

	| lineString parsed context response method params reqVersion |

	lineString :=
		(aLine isKindOf: ByteArray)
			ifTrue: [(UnicodeString utf8: aLine) asString]
			ifFalse: [aLine asString].
	lineString isEmpty ifTrue: [^self].
	parsed :=
		[McpJSONReader fromString: lineString]
			on: Error
			do: [:e | | errResp |
				errResp :=
					EsOrderedDictionary new
						at: 'jsonrpc' put: '2.0';
						at: 'id' put: nil;
						at: 'error'
							put: (
								EsOrderedDictionary new
									at: 'code' put: McpJsonRpcParseErrorCode;
									at: 'message' put: 'Parse error';
									yourself);
						yourself.
				self sendResponse: errResp.
				^self].
	(parsed isKindOf: KeyedCollection)
		ifFalse: [| errResp |
			errResp :=
				EsOrderedDictionary new
					at: 'jsonrpc' put: '2.0';
					at: 'id' put: nil;
					at: 'error'
						put: (
							EsOrderedDictionary new
								at: 'code' put: McpJsonRpcInvalidRequestCode;
								at: 'message' put: 'Invalid Request';
								yourself);
					yourself.
			self sendResponse: errResp.
			^self].
	context := McpServerRequestContext new.
	context transportRequest: parsed.
	method := parsed at: 'method' ifAbsent: [nil].
	params := parsed at: 'params' ifAbsent: [nil].
	reqVersion := self extractProtocolVersionFrom: method params: params.
	self extractMetaParametersFrom: params into: context.
	context protocolVersion: reqVersion.
	response := self dispatcher dispatch: parsed context: context.
	(method = 'initialize' and: [response notNil and: [(response includesKey: 'error') not]])
		ifTrue: [| result |
			result := response at: 'result' ifAbsent: [nil].
			(result isKindOf: KeyedCollection)
				ifTrue: [
					negotiatedProtocolVersion := result at: 'protocolVersion' ifAbsent: [nil]]].
	response ifNotNil: [self sendResponse: response].
	^self
]

{ #category : 'IO Loops' }
McpStdioServer >> runLoop [
	"Process lines from inputStream until closed or stream ends.

	 Answers:
		<McpStdioServer> the receiver."

	[self isRunning and: [self inputStream notNil and: [self inputStream atEnd not]]] whileTrue: [|
		  line |
		line :=
			(self inputStream respondsTo: 'nextLine')
				ifTrue: [self inputStream nextLine]
				ifFalse: [self inputStream upTo: Character lf].
		line ifNotNil: [self processMessage: line]].
	isRunning := false.
	^self
]

{ #category : 'Sending' }
McpStdioServer >> sendResponse: aDictionary [
	"Format and write one JSON-RPC response line to outputStream.

	 Arguments:
		aDictionary - <KeyedCollection> response to write.
	 Answers:
		<McpStdioServer> the receiver."

	| jsonString |

	jsonString := String streamContents: [:s | (McpJSONWriter on: s) nextPut: aDictionary].
	self outputStream
		nextPutAll: jsonString;
		nextPutAll: (String with: Character lf);
		flush.
	^self
]

{ #category : 'Accessing' }
McpStdioServer >> server [
	"Answer the hosted MCP server.

	 Answers:
		<McpServer> or nil."

	^server
]

{ #category : 'Accessing' }
McpStdioServer >> server: anMcpServer [
	"Set the MCP server to host.

	 Arguments:
		anMcpServer - <McpServer>.
	 Answers:
		<McpStdioServer> the receiver."

	(anMcpServer isKindOf: McpServer)
		ifFalse: [self error: 'Stdio server requires an McpServer instance'].
	server := anMcpServer.
	dispatcher := nil.
	^self
]

{ #category : 'Starting and Stopping' }
McpStdioServer >> start [
	"Start the stdio request-processing loop in a background process.

	 Answers:
		<McpStdioServer> the receiver."

	self isRunning ifTrue: [^self].
	isRunning := true.
	process := [self runLoop] fork.
	^self
]

{ #category : 'Starting and Stopping' }
McpStdioServer >> stop [
	"Stop the stdio server process.

	 Answers:
		<McpStdioServer> the receiver."

	isRunning := false.
	process ifNotNil: [
		process terminate.
		process := nil].
	^self
]
