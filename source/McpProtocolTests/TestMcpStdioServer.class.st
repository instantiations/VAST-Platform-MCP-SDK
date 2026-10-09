Class {
	#name : 'TestMcpStdioServer',
	#superclass : 'TestCase',
	#instVars : [
		'stdioServer',
		'server',
		'inStream',
		'outStream'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Initialization' }
TestMcpStdioServer >> setUp [
	"Prepare server and stream fixtures.

	 Answers:
		<TestMcpStdioServer> the receiver."

	| tool |

	super setUp.
	server := McpServer new.
	tool :=
		McpBlockTool new
			name: 'add';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args | (((args at: 'a') + (args at: 'b')) printString)];
			yourself.
	server toolRegistry registerTool: tool.
	outStream := WriteStream on: String new.
	stdioServer :=
		McpStdioServer new
			server: server;
			outputStream: outStream;
			yourself.
	^self
]

{ #category : 'Running' }
TestMcpStdioServer >> tearDown [
	"Clean up server.

	 Answers:
		<TestMcpStdioServer> the receiver."

	stdioServer ifNotNil: [stdioServer stop].
	super tearDown
]

{ #category : 'Testing' }
TestMcpStdioServer >> testStdioServerPreservesNegotiatedProtocolVersion [
	"McpStdioServer preserves the negotiated handshake protocol version rather than forcing modern 2026-07-28."

	| initRequest initResponse parsedInit toolRequest toolResponse parsedTool result |

	initRequest :=
		'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"testClient","version":"1.0"}}}'.
	stdioServer processMessage: initRequest.
	initResponse := outStream contents.
	parsedInit := McpJSONReader fromString: initResponse trimBlanks.
	self assert: ((parsedInit at: 'result') at: 'protocolVersion') equals: '2024-11-05'.

	outStream := WriteStream on: String new.
	stdioServer outputStream: outStream.
	stdioServer processMessage: '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'.

	outStream := WriteStream on: String new.
	stdioServer outputStream: outStream.
	toolRequest :=
		'{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"add","arguments":{"a":10,"b":20}}}'.
	stdioServer processMessage: toolRequest.
	toolResponse := outStream contents.
	parsedTool := McpJSONReader fromString: toolResponse trimBlanks.
	result := parsedTool at: 'result'.
	self assert: (((result at: 'content') first at: 'text')) equals: '30'.
	self assert: (result includesKey: 'resultType') not.
	self assert: (result includesKey: '_meta') not
]

{ #category : 'Testing' }
TestMcpStdioServer >> testStdioServerProcessesToolCall [
	"McpStdioServer reads a JSON-RPC request line and writes a single-line JSON-RPC response."

	| requestLine responseLine parsedResponse |

	requestLine :=
		'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"add","arguments":{"a":10,"b":20}}}'.
	stdioServer processMessage: requestLine.

	responseLine := outStream contents.
	self assert: responseLine last equals: Character lf.
	parsedResponse := McpJSONReader fromString: responseLine trimBlanks.
	self assert: (parsedResponse at: 'id') equals: 1.
	self assert: (parsedResponse at: 'jsonrpc') equals: '2.0'.
	self assert: (((parsedResponse at: 'result') at: 'content') first at: 'text') equals: '30'
]

{ #category : 'Testing' }
TestMcpStdioServer >> testStdioServerRejectsMalformedJson [
	"McpStdioServer returns a JSON-RPC parse error for malformed lines."

	| parsedResponse |

	stdioServer processMessage: 'not valid json'.

	parsedResponse := McpJSONReader fromString: outStream contents trimBlanks.
	self assert: (parsedResponse at: 'jsonrpc') equals: '2.0'.
	self assert: ((parsedResponse at: 'error') at: 'code') equals: McpJsonRpcParseErrorCode
]
