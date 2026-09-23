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
	#category : 'VastMcpProtocolTests'
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
