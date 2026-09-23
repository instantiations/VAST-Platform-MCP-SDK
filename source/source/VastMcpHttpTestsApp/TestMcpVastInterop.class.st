Class {
	#name : 'TestMcpVastInterop',
	#superclass : 'TestCase',
	#instVars : [
		'servers',
		'clients'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'VastMcpHttpTestsApp'
}

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropCloseIsIdempotent: client [
    "Exercise CloseIsIdempotent through the connected client API."

    self assert: (self stdioInteropEcho: 'before-close' using: client)
        equals: 'before-close'.
    client close.
    self deny: client isConnected.
    client close.
    self deny: client isConnected
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropCompletions: client [
    "Exercise Completions through the connected client API."

    | completion context |
    completion := client completePrompt: 'greet' argument: 'person' value: 'Al'.
    self assert: (completion at: 'values') asArray equals: #('Alice' 'Alfred').
    completion := client completePrompt: 'greet' argument: 'person' value: 'Z'.
    self assert: (completion at: 'values') isEmpty.
    context := EsOrderedDictionary with: 'arguments' ->
        (EsOrderedDictionary with: 'chosen' -> '42').
    completion := client completeResource: 'test://interop/items/{id}'
        argument: 'id' value: '4' context: context.
    self assert: (completion at: 'values') asArray equals: #('42')
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropErrorRecovery: client [
    "Exercise ErrorRecovery through the connected client API."

    | code result |
    code := nil.
    [client sendRequest: 'interop/missing' params: EsOrderedDictionary new]
        on: McpJsonRpcError do: [:error | code := error code].
    self assert: code equals: -32601.
    code := nil.
    [client getPrompt: 'missing' arguments: EsOrderedDictionary new]
        on: McpJsonRpcError do: [:error | code := error code].
    self assert: code equals: -32602.
    code := nil.
    [client getPrompt: 'greet' arguments: EsOrderedDictionary new]
        on: McpJsonRpcError do: [:error | code := error code].
    self assert: code equals: -32602.
    self assert: (self stdioInteropEcho: 'after-rpc' using: client)
        equals: 'after-rpc'.
    result := client callTool: 'fail' arguments: EsOrderedDictionary new.
    self assert: (result at: 'isError') equals: true.
    self assert: ((result at: 'content') first at: 'text')
        equals: 'Deliberate capability failure'.
    self assert: (self stdioInteropEcho: 'after-tool' using: client)
        equals: 'after-tool'
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropPrompts: client [
    "Exercise Prompts through the connected client API."

    | result message text |
    text := self interopUnicodeText.
    self assert: client listPrompts size equals: 1.
    self assert: (client listPrompts first at: 'name') equals: 'greet'.
    result := client getPrompt: 'greet'
        arguments: (EsOrderedDictionary with: 'person' -> text).
    self assert: (result at: 'messages') size equals: 1.
    message := (result at: 'messages') first.
    self assert: (message at: 'role') equals: 'user'.
    self assert: ((message at: 'content') at: 'type') equals: 'text'.
    self assert: ((message at: 'content') at: 'text') asUtf8Bytes
        equals: text asUtf8Bytes
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropResourceTemplates: client [
    "Exercise ResourceTemplates through the connected client API."

    | listed content |
    listed := client listResourceTemplates.
    self assert: listed size equals: 1.
    self assert: (listed first at: 'uriTemplate')
        equals: 'test://interop/items/{id}'.
    content := ((client readResource: 'test://interop/items/42')
        at: 'contents') first.
    self assert: (content at: 'uri') equals: 'test://interop/items/42'.
    self assert: (content at: 'text') equals: '42'
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropResources: client [
    "Exercise Resources through the connected client API."

    | content listed |
    listed := client listResources.
    self assert: listed size equals: 2.
    self assert: (listed anySatisfy: [:each |
        (each at: 'uri') = 'test://interop/text']).
    content := ((client readResource: 'test://interop/text') at: 'contents').
    self assert: content size equals: 1.
    self assert: (content first at: 'uri') equals: 'test://interop/text'.
    self assert: (content first at: 'mimeType') equals: 'text/plain'.
    self assert: (content first at: 'text') asUtf8Bytes
        equals: self interopUnicodeText asUtf8Bytes.
    content := ((client readResource: 'test://interop/binary') at: 'contents').
    self assert: content size equals: 1.
    self assert: (content first at: 'mimeType')
        equals: 'application/octet-stream'.
    self assert: (Base64Coder current decodeAsByteArray:
        (content first at: 'blob')) equals: #[0 1 2 255]
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> assertCapabilityInteropUnicodeAndCorrelation: client [
    "Exercise UnicodeAndCorrelation through the connected client API."

    | text result |
    text := self interopUnicodeText.
    1 to: 6 do: [:index |
        result := self stdioInteropEcho: text , index printString using: client.
        self assert: result asUtf8Bytes
            equals: (text , index printString) asUtf8Bytes]
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpVastInterop >> decodeStdioInteropLine: bytes [
	"Decode one physical JSON line recorded by the stream fixture."

	self deny: (bytes includes: Character lf value).
	^NeoJSONReader fromString: (UnicodeString utf8: bytes) asString
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> interopTextResource: uri text: text [
    "Build the wire result for a concrete or template resource."

    | content |

    content := EsOrderedDictionary new
        at: 'uri' put: uri;
        at: 'mimeType' put: 'text/plain';
        at: 'text' put: text;
        yourself.
    ^EsOrderedDictionary with: 'contents' -> (Array with: content)
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> interopUnicodeText [
    "Include combining scalars, supplementary Unicode and escaped controls."

    ^(UnicodeString utf8:
        #(99 97 102 195 169 32 101 204 129 32 230 151 165 230 156 172
          32 240 159 152 128 32 34 92 9 13 10 0 8 12) asByteArray) asString
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> newCapabilityInteropClientFor: kind [
    "Use real HTTP/SSE sockets or the existing in-image stdio adapter.
    Port 8916 is reserved for these sequential integration tests."

    | server endpoint transport client legacy |

    server := self newCapabilityInteropServer.
    legacy := #(stdioLegacy httpLegacy sseLegacy) includes: kind.
    client := legacy ifTrue: [McpClient legacy] ifFalse: [McpClient modern].
    clients add: client.
    (#(stdioModern stdioLegacy) includes: kind)
        ifTrue: [
            endpoint := McpStdioServer forServer: server.
            servers add: endpoint.
            transport := McpInteropStdioClientTransport new.
            transport requestTimeout: 5.
            client transport: transport.
            transport attachToServer: endpoint]
        ifFalse: [
            endpoint := McpHttpServer new
                port: 8916; mcpServer: server; yourself.
            servers add: endpoint.
            endpoint start.
            kind = #sseLegacy
                ifTrue: [
                    transport := McpLegacySseClientTransport
                        url: 'http://127.0.0.1:8916/sse'.
                    transport requestTimeout: 5]
                ifFalse: [
                    transport := McpHttpClientTransport
                        url: 'http://127.0.0.1:8916/mcp'.
                    transport requestTimeout: 5000].
            client transport: transport].
    client connect.
    self assert: client isConnected.
    self assert: (McpProtocolVersion isModern: client protocolVersion)
        equals: legacy not.
    #('tools' 'prompts' 'resources' 'completions') do: [:capability |
        self assert: (client serverCapabilities includesKey: capability)].
    ^client
]

{ #category : 'Private',
  #vaVisibility : 'private' }
TestMcpVastInterop >> newCapabilityInteropServer [
    "Register all providers before discovery or initialize."

    | server prompt template |

    server := McpServer new name: 'VastCapabilityInterop'; version: '1.0.0';
        yourself.
    server toolRegistry registerTool: (McpBlockTool new
        name: 'echo';
        inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
        block: [:args | args at: 'text']; yourself).
    server toolRegistry registerTool: (McpBlockTool new
        name: 'fail';
        inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
        block: [self error: 'Deliberate capability failure']; yourself).
    prompt := McpBlockPrompt new
        name: 'greet';
        arguments: (Array with: (EsOrderedDictionary
            with: 'name' -> 'person' with: 'required' -> true));
        block: [:args | | content message |
            content := EsOrderedDictionary
                with: 'type' -> 'text' with: 'text' -> (args at: 'person').
            message := EsOrderedDictionary
                with: 'role' -> 'user' with: 'content' -> content.
            EsOrderedDictionary with: 'messages' -> (Array with: message)];
        completionBlock: [:name :prefix :context |
            (name = 'person' and: [prefix = 'Al'])
                ifTrue: [#('Alice' 'Alfred')] ifFalse: [#()]];
        yourself.
    server promptRegistry registerPrompt: prompt.
    server resourceRegistry registerResource: (McpBlockResource new
        uri: 'test://interop/text'; name: 'text'; mimeType: 'text/plain';
        block: [self interopTextResource: 'test://interop/text'
            text: self interopUnicodeText]; yourself).
    server resourceRegistry registerResource: (McpBlockResource new
        uri: 'test://interop/binary'; name: 'binary';
        mimeType: 'application/octet-stream';
        block: [EsOrderedDictionary with: 'contents' -> (Array with:
            (EsOrderedDictionary new
                at: 'uri' put: 'test://interop/binary';
                at: 'mimeType' put: 'application/octet-stream';
                at: 'blob' put: 'AAEC/w=='; yourself))]; yourself).
    template := McpBlockResourceTemplate new
        uriTemplate: 'test://interop/items/{id}'; name: 'items';
        readBlock: [:uri :context |
            self interopTextResource: uri
                text: ((context ifNil: [
                (McpUriTemplate template: 'test://interop/items/{id}')
                    matchUri: uri] ifNotNil: [context metadata at: 'variables'])
                        at: 'id')];
        completionBlock: [:name :prefix :context |
            (name = 'id' and: [prefix = '4'])
                ifTrue: [Array with: ((context at: 'arguments') at: 'chosen')]
                ifFalse: [#()]];
        yourself.
    server resourceTemplateRegistry registerTemplate: template.
    ^server
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpVastInterop >> newStdioInteropClientInMode: aMode [
	"Create an isolated echo/failure server and register cleanup first."

	| server stdio transport client properties schema |

	server :=
		McpServer new
			name: 'VastStdioInterop';
			version: '1.0.0';
			yourself.
	properties := EsOrderedDictionary with: 'text' -> (EsOrderedDictionary with: 'type' -> 'string').
	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			at: 'required' put: #('text');
			at: 'additionalProperties' put: false;
			yourself.
	server toolRegistry registerTool: (
		McpBlockTool new
			name: 'echo';
			inputSchema: schema;
			block: [:arguments | arguments at: 'text'];
			yourself).
	server toolRegistry registerTool: (
		McpBlockTool new
			name: 'fail';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [self error: 'Deliberate stdio tool failure'];
			yourself).
	stdio := McpStdioServer forServer: server.
	servers add: stdio.
	transport := McpInteropStdioClientTransport new.
	transport requestTimeout: 5.
	client := aMode = #legacy ifTrue: [McpClient legacy] ifFalse: [McpClient modern].
	clients add: client.
	client transport: transport.
	transport attachToServer: stdio.
	client connect.
	^client
]

{ #category : 'Running' }
TestMcpVastInterop >> setUp [
	"Prepare tracking collections for servers and clients."

	super setUp.
	servers := OrderedCollection new.
	clients := OrderedCollection new
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpVastInterop >> stdioInteropEcho: text using: client [
	"Execute a real serialized tool call and answer its text content."

	| result content |

	result := client callTool: 'echo' arguments: (EsOrderedDictionary with: 'text' -> text).
	self assert: (result at: 'isError') equals: false.
	content := result at: 'content'.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	^content first at: 'text'
]

{ #category : 'Running' }
TestMcpVastInterop >> tearDown [
	"Safely stop all started HTTP servers and close connected clients."

	clients do: [:c | [c close] on: Exception do: [:ex | ex exitWith: nil]].
	servers do: [:s | [s stop] on: Exception do: [:ex | ex exitWith: nil]].
	super tearDown
]

{ #category : 'Integration Tests' }
TestMcpVastInterop >> testSessionGroupAggregatesMultipleVastServers [
	"Live end-to-end: McpSessionGroup aggregates multiple independent McpHttpServers."

	| serverA toolA httpA serverB toolB httpB clientA clientB group tools resA resB |

	serverA :=
		McpServer new
			name: 'ServerAlpha';
			version: '1.0';
			yourself.
	toolA :=
		McpBlockTool new
			name: 'op';
			block: ['from_Alpha'];
			yourself.
	serverA toolRegistry registerTool: toolA.
	httpA :=
		McpHttpServer new
			port: 8912;
			mcpServer: serverA;
			start.
	servers add: httpA.

	serverB :=
		McpServer new
			name: 'ServerBeta';
			version: '1.0';
			yourself.
	toolB :=
		McpBlockTool new
			name: 'op';
			block: ['from_Beta'];
			yourself.
	serverB toolRegistry registerTool: toolB.
	httpB :=
		McpHttpServer new
			port: 8913;
			mcpServer: serverB;
			start.
	servers add: httpB.

	clientA := McpClient modern.
	clientA transport: (McpHttpClientTransport url: 'http://127.0.0.1:8912/mcp').
	clients add: clientA.

	clientB := McpClient modern.
	clientB transport: (McpHttpClientTransport url: 'http://127.0.0.1:8913/mcp').
	clients add: clientB.

	group := McpSessionGroup new prefixToolNamesWithServerName.
	group addClient: clientA.
	group addClient: clientB.

	tools := group listTools.
	self assert: (tools anySatisfy: [:t | (t at: 'name') = 'ServerAlpha_op']).
	self assert: (tools anySatisfy: [:t | (t at: 'name') = 'ServerBeta_op']).

	resA := group callTool: 'ServerAlpha_op' arguments: EsOrderedDictionary new.
	resB := group callTool: 'ServerBeta_op' arguments: EsOrderedDictionary new.

	self assert: (((resA at: 'content') first) at: 'text') equals: 'from_Alpha'.
	self assert: (((resB at: 'content') first) at: 'text') equals: 'from_Beta'.
	group close
]

{ #category : 'Integration Tests' }
TestMcpVastInterop >> testVastClientConnectsToVastHttpServer [
	"Live end-to-end: McpClient connects to in-image McpHttpServer over real Streamable HTTP."

	| mcpServer tool httpServer client tools result |

	mcpServer :=
		McpServer new
			name: 'VastTestHttpServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'add';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args | (((args at: 'a') + (args at: 'b')) printString)];
			yourself.
	mcpServer toolRegistry registerTool: tool.

	httpServer :=
		McpHttpServer new
			port: 8910;
			mcpServer: mcpServer;
			start.
	servers add: httpServer.

	client := McpClient modern.
	client transport: (McpHttpClientTransport url: 'http://127.0.0.1:8910/mcp').
	clients add: client.
	client connect.

	self assert: client isConnected.
	self assert: (McpProtocolVersion isModern: client protocolVersion).

	tools := client listTools.
	self assert: (tools anySatisfy: [:t | (t at: 'name') = 'add']).

	result := client callTool: 'add' arguments: (EsOrderedDictionary with: 'a' -> 25 with: 'b' -> 17).
	self assert: (result at: 'isError') equals: false.
	self assert: (((result at: 'content') first at: 'text') includesSubstring: '42')
]

{ #category : 'Integration Tests' }
TestMcpVastInterop >> testVastClientHttpMultiRoundTripResolution [
	"Live end-to-end: Multi-round-trip parameter resolver executed across HTTP network socket."

	| mcpServer tool httpServer client result |

	mcpServer :=
		McpServer new
			name: 'VastMrtrServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'request_qty';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'quantity'
				with: [:ctx :args |
					(ctx notNil and: [
						ctx inputResponses notNil and: [ctx inputResponses includesKey: 'quantity']])
							ifTrue: [ctx inputResponses at: 'quantity']
							ifFalse: [McpElicit message: 'How many items?']];
			block: [:args | 'Processed ' , (args at: 'quantity') printString , ' items'];
			yourself.
	mcpServer toolRegistry registerTool: tool.

	httpServer :=
		McpHttpServer new
			port: 8914;
			mcpServer: mcpServer;
			start.
	servers add: httpServer.

	client := McpClient modern.
	client transport: (McpHttpClientTransport url: 'http://127.0.0.1:8914/mcp').
	client elicitationCallback: [:req :c | 12].
	clients add: client.
	client connect.

	result := client callTool: 'request_qty' arguments: EsOrderedDictionary new.
	self assert: (result at: 'isError') equals: false.
	self assert: (((result at: 'content') first at: 'text') equals: 'Processed 12 items')
]

{ #category : 'Integration Tests' }
TestMcpVastInterop >> testVastClientSubscriptionsListenOverHttp [
	"Live end-to-end: Subscriptions/listen stream and change event notifications over HTTP."

	| mcpServer tool httpServer client receivedNotification limit |

	mcpServer :=
		McpServer new
			name: 'VastEventServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'initial';
			block: ['ok'];
			yourself.
	mcpServer toolRegistry registerTool: tool.

	httpServer :=
		McpHttpServer new
			port: 8915;
			mcpServer: mcpServer;
			start.
	servers add: httpServer.

	client := McpClient modern.
	client transport: (McpHttpClientTransport url: 'http://127.0.0.1:8915/mcp').
	clients add: client.
	client connect.

	client responseCache
		set: 'tools/list'
		key: ''
		value: (EsOrderedDictionary with: 'tools' -> #())
		ttlMs: 60000
		scope: 'public'.
	self assert: client responseCache size equals: 1.

	receivedNotification := false.
	client
		listen: (EsOrderedDictionary with: 'toolsListChanged' -> true)
		do: [:method :params | receivedNotification := true].

	mcpServer notifyToolsChanged.

	limit := 20.
	[receivedNotification not and: [limit > 0]] whileTrue: [
		(Delay forMilliseconds: 50) wait.
		limit := limit - 1].

	self assert: client responseCache size equals: 0.
	self assert: receivedNotification
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastHttpServletPreservesStreamingWriter [
    "A live subscriptions stream must not acquire a finite Content-Length."

    | request writer result |

    request := McpHttpServerTestRequest new.
    writer := [:connection | connection].
    result := McpHttpServlet new responseEntity: writer for: request.
    self assert: result == writer.
    self assert: request header responseHeader contentLength isNil
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastHttpServletWritesUtf8ResponseBytes [
    "The actual servlet boundary must preserve bytes and Content-Length."

    | request writer connection stream text |

    request := McpHttpServerTestRequest new.
    text := self interopUnicodeText.
    writer := McpHttpServlet new responseEntity: text for: request.
    stream := WriteStream on: ByteArray new.
    connection := SstHttpConnection new stream: stream; yourself.
    writer value: connection.
    self assert: stream contents equals: text asUtf8Bytes.
    self assert: request header responseHeader contentLength
        equals: text asUtf8Bytes size
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastJsonPreservesCrlfWithAsciiEscapes [
    "Isolate JSON serialization from transport framing."

    | json text decoded crlf |

    crlf := UnicodeString utf8: #[13 10].
    json := String streamContents: [:stream |
        (NeoJSONWriter on: stream) asciiOnly: true; nextPut: crlf].
    self assert: json asUtf8Bytes equals: #[34 92 114 92 110 34].
    text := self interopUnicodeText.
    json := String streamContents: [:stream |
        (NeoJSONWriter on: stream) asciiOnly: true; nextPut: text].
    decoded := NeoJSONReader fromString: json.
    self assert: decoded asUtf8Bytes equals: text asUtf8Bytes
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastJsonPreservesCrlfWithUnicodeOutput [
    "Isolate JSON serialization from transport framing."

    | json text decoded crlf |

    crlf := UnicodeString utf8: #[13 10].
    json := String streamContents: [:stream |
        (NeoJSONWriter on: stream) asciiOnly: false; nextPut: crlf].
    self assert: json asUtf8Bytes equals: #[34 92 114 92 110 34].
    text := self interopUnicodeText.
    json := String streamContents: [:stream |
        (NeoJSONWriter on: stream) asciiOnly: false; nextPut: text].
    decoded := NeoJSONReader fromString: json.
    self assert: decoded asUtf8Bytes equals: text asUtf8Bytes
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyClientConnectsToVastStdioServer [
	"Exercise initialize and its notification before a tool exchange."

	| client requests first second |

	client := self newStdioInteropClientInMode: #legacy.
	self assert: client isConnected.
	self deny: (McpProtocolVersion isModern: client protocolVersion).
	self assert: (self stdioInteropEcho: 'legacy' using: client) equals: 'legacy'.
	requests := client transport requestLines.
	first := self decodeStdioInteropLine: requests first.
	second := self decodeStdioInteropLine: (requests at: 2).
	self assert: (first at: 'method') equals: 'initialize'.
	self assert: (second at: 'method') equals: 'notifications/initialized'.
	self deny: (second includesKey: 'id').
	self assert: client transport responseLines size equals: 2
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpCloseIsIdempotent [
    "Run the CloseIsIdempotent scenario using LegacyHttp."

    self assertCapabilityInteropCloseIsIdempotent:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpCompletions [
    "Run the Completions scenario using LegacyHttp."

    self assertCapabilityInteropCompletions:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpErrorRecovery [
    "Run the ErrorRecovery scenario using LegacyHttp."

    self assertCapabilityInteropErrorRecovery:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpPrompts [
    "Run the Prompts scenario using LegacyHttp."

    self assertCapabilityInteropPrompts:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpResourceTemplates [
    "Run the ResourceTemplates scenario using LegacyHttp."

    self assertCapabilityInteropResourceTemplates:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpResources [
    "Run the Resources scenario using LegacyHttp."

    self assertCapabilityInteropResources:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyHttpUnicodeAndCorrelation [
    "Run the UnicodeAndCorrelation scenario using LegacyHttp."

    self assertCapabilityInteropUnicodeAndCorrelation:
        (self newCapabilityInteropClientFor: #httpLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseCloseIsIdempotent [
    "Run the CloseIsIdempotent scenario using LegacySse."

    self assertCapabilityInteropCloseIsIdempotent:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseCompletions [
    "Run the Completions scenario using LegacySse."

    self assertCapabilityInteropCompletions:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseDecodesRawByteStringsAtEverySplit [
    "Exercise the real transport entry with every possible two-chunk split."

    | text json frame received client transport |

    text := self interopUnicodeText.
    json := NeoJSONWriter toString: (EsOrderedDictionary new
        at: 'jsonrpc' put: '2.0';
        at: 'method' put: 'notifications/interop';
        at: 'params' put: (EsOrderedDictionary with: 'text' -> text);
        yourself).
    frame := ('event: message' , String crlf , 'data: ' , json ,
        String crlf , String crlf) asUtf8Bytes.
    1 to: frame size - 1 do: [:split |
        received := OrderedCollection new.
        client := McpClient legacy.
        client onNotification: 'notifications/interop'
            do: [:params | received add: (params at: 'text')].
        transport := McpLegacySseClientTransport new.
        client transport: transport.
        [
            transport handleStreamChunk: (frame copyFrom: 1 to: split) asString.
            transport handleStreamChunk:
                (frame copyFrom: split + 1 to: frame size) asString.
            self assert: received size equals: 1.
            self assert: received first asUtf8Bytes equals: text asUtf8Bytes
        ] ensure: [client close]]
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseErrorRecovery [
    "Run the ErrorRecovery scenario using LegacySse."

    self assertCapabilityInteropErrorRecovery:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySsePrompts [
    "Run the Prompts scenario using LegacySse."

    self assertCapabilityInteropPrompts:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseResourceTemplates [
    "Run the ResourceTemplates scenario using LegacySse."

    self assertCapabilityInteropResourceTemplates:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseResources [
    "Run the Resources scenario using LegacySse."

    self assertCapabilityInteropResources:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacySseUnicodeAndCorrelation [
    "Run the UnicodeAndCorrelation scenario using LegacySse."

    self assertCapabilityInteropUnicodeAndCorrelation:
        (self newCapabilityInteropClientFor: #sseLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioCloseIsIdempotent [
    "Run the CloseIsIdempotent scenario using LegacyStdio."

    self assertCapabilityInteropCloseIsIdempotent:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioCompletions [
    "Run the Completions scenario using LegacyStdio."

    self assertCapabilityInteropCompletions:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioErrorRecovery [
    "Run the ErrorRecovery scenario using LegacyStdio."

    self assertCapabilityInteropErrorRecovery:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioPrompts [
    "Run the Prompts scenario using LegacyStdio."

    self assertCapabilityInteropPrompts:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioResourceTemplates [
    "Run the ResourceTemplates scenario using LegacyStdio."

    self assertCapabilityInteropResourceTemplates:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioResources [
    "Run the Resources scenario using LegacyStdio."

    self assertCapabilityInteropResources:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastLegacyStdioUnicodeAndCorrelation [
    "Run the UnicodeAndCorrelation scenario using LegacyStdio."

    self assertCapabilityInteropUnicodeAndCorrelation:
        (self newCapabilityInteropClientFor: #stdioLegacy)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernClientConnectsToVastStdioServer [
	"Discover, list tools and execute through the real stdio run loop."

	| client tools request |

	client := self newStdioInteropClientInMode: #modern.
	self assert: client isConnected.
	self assert: (McpProtocolVersion isModern: client protocolVersion).
	request := self decodeStdioInteropLine: client transport requestLines first.
	self assert: (request at: 'method') equals: 'server/discover'.
	tools := client listTools.
	self assert: (tools anySatisfy: [:tool | (tool at: 'name') = 'echo']).
	self assert: (self stdioInteropEcho: 'pong' using: client) equals: 'pong'
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpCloseIsIdempotent [
    "Run the CloseIsIdempotent scenario using ModernHttp."

    self assertCapabilityInteropCloseIsIdempotent:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpCompletions [
    "Run the Completions scenario using ModernHttp."

    self assertCapabilityInteropCompletions:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpErrorRecovery [
    "Run the ErrorRecovery scenario using ModernHttp."

    self assertCapabilityInteropErrorRecovery:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpPrompts [
    "Run the Prompts scenario using ModernHttp."

    self assertCapabilityInteropPrompts:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpResourceTemplates [
    "Run the ResourceTemplates scenario using ModernHttp."

    self assertCapabilityInteropResourceTemplates:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpResources [
    "Run the Resources scenario using ModernHttp."

    self assertCapabilityInteropResources:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernHttpUnicodeAndCorrelation [
    "Run the UnicodeAndCorrelation scenario using ModernHttp."

    self assertCapabilityInteropUnicodeAndCorrelation:
        (self newCapabilityInteropClientFor: #httpModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioCloseIsIdempotent [
    "Run the CloseIsIdempotent scenario using ModernStdio."

    self assertCapabilityInteropCloseIsIdempotent:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioCompletions [
    "Run the Completions scenario using ModernStdio."

    self assertCapabilityInteropCompletions:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioErrorRecovery [
    "Run the ErrorRecovery scenario using ModernStdio."

    self assertCapabilityInteropErrorRecovery:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioMultiRoundTripResolution [
	"Live end-to-end: Multi-round-trip parameter resolver executed across the stdio adapter."

	| mcpServer tool stdioServer client result |

	mcpServer :=
		McpServer new
			name: 'VastMrtrServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'request_qty';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'quantity'
				with: [:ctx :args |
					(ctx notNil and: [
						ctx inputResponses notNil and: [ctx inputResponses includesKey: 'quantity']])
							ifTrue: [ctx inputResponses at: 'quantity']
							ifFalse: [McpElicit message: 'How many items?']];
			block: [:args | 'Processed ' , (args at: 'quantity') printString , ' items'];
			yourself.
	mcpServer toolRegistry registerTool: tool.

	stdioServer := McpStdioServer forServer: mcpServer.
	servers add: stdioServer.
	client := McpClient modern.
	clients add: client.
	client transport: (McpInteropStdioClientTransport new requestTimeout: 5;
		yourself).
	client transport attachToServer: stdioServer.
	client elicitationCallback: [:req :c | 12].
	client connect.

	result := client callTool: 'request_qty' arguments: EsOrderedDictionary new.
	self assert: (result at: 'isError') equals: false.
	self assert: (((result at: 'content') first at: 'text') equals: 'Processed 12 items')
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioPrompts [
    "Run the Prompts scenario using ModernStdio."

    self assertCapabilityInteropPrompts:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioResourceTemplates [
    "Run the ResourceTemplates scenario using ModernStdio."

    self assertCapabilityInteropResourceTemplates:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioResources [
    "Run the Resources scenario using ModernStdio."

    self assertCapabilityInteropResources:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastModernStdioUnicodeAndCorrelation [
    "Run the UnicodeAndCorrelation scenario using ModernStdio."

    self assertCapabilityInteropUnicodeAndCorrelation:
        (self newCapabilityInteropClientFor: #stdioModern)
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastSseByteParserPreservesFramesAndPartialTail [
    "One-byte chunks cover split CRLF, LF, CR and incomplete UTF-8 tails."

    | parser pending events payload frame bytes tail |

    parser := McpSseParser new.
    pending := #[].
    events := OrderedCollection new.
    payload := (UnicodeString utf8: #[240 159 152 128]) asString.
    bytes := #[].
    (Array with: #[10] with: #[13 10] with: #[13]) do: [:ending |
        frame := 'data: ' asUtf8Bytes , payload asUtf8Bytes , ending , ending.
        bytes := bytes , frame].
    tail := 'data: ' asUtf8Bytes , #[240 159].
    bytes := bytes , tail.
    bytes do: [:byte |
        pending := parser parseAvailableBytes: pending , (ByteArray with: byte)
            do: [:event | events add: event]].
    self assert: events size equals: 3.
    events do: [:event |
        self assert: event data asUtf8Bytes equals: payload asUtf8Bytes].
    self assert: pending equals: tail
]

{ #category : 'Integration Tests' }
TestMcpVastInterop >> testVastSseClientConnectsToVastSseServer [
	"Live end-to-end: McpLegacySseClientTransport connects to McpHttpServer over dual-endpoint SSE."

	| mcpServer tool httpServer client tools result |

	mcpServer :=
		McpServer new
			name: 'VastTestSseServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'ping_tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args | 'pong'];
			yourself.
	mcpServer toolRegistry registerTool: tool.

	httpServer :=
		McpHttpServer new
			port: 8911;
			mcpServer: mcpServer;
			start.
	servers add: httpServer.

	client := McpClient legacy.
	client transport: (McpLegacySseClientTransport url: 'http://127.0.0.1:8911/sse').
	clients add: client.
	client connect.

	self assert: client isConnected.

	tools := client listTools.
	self assert: (tools anySatisfy: [:t | (t at: 'name') = 'ping_tool']).

	result := client callTool: 'ping_tool' arguments: EsOrderedDictionary new.
	self assert: (((result at: 'content') first at: 'text') equals: 'pong')
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioClientCloseStopsFixtureServer [
    "Closing a connected fixture releases both reader and server workers."

    | client stdio |

    client := self newStdioInteropClientInMode: #modern.
    stdio := servers last.
    self assert: client transport isRunning.
    client close.
    self deny: client isConnected.
    self deny: client transport isRunning.
    self deny: stdio isRunning.
    client close.
    self deny: stdio isRunning
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioCorrelatesRepeatedToolCalls [
	"Distinct calls on one connection produce unique correlated replies."

	| client requests responses ids |

	client := self newStdioInteropClientInMode: #modern.
	1 to: 12 do: [:index | | value |
		value := 'message-' , index printString.
		self assert: (self stdioInteropEcho: value using: client) equals: value].
	requests := client transport requestLines.
	responses := client transport responseLines.
	self assert: requests size equals: 13.
	self assert: responses size equals: requests size.
	ids := Set new.
	1 to: requests size do: [:index | | request response identifier |
		request := self decodeStdioInteropLine: (requests at: index).
		response := self decodeStdioInteropLine: (responses at: index).
		identifier := request at: 'id'.
		self deny: (ids includes: identifier).
		ids add: identifier.
		self assert: (response at: 'id') equals: identifier]
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioFixtureAcceptsCharacterAndByteDelimiters [
    "Exercise both branches without sending asciiValue to Character."

    | stream |

    stream := McpInteropStdioStream new.
    [
        stream nextPutAll: #[97 10 98 10]; flush; close.
        self assert: (stream upTo: Character lf) equals: #[97].
        self assert: (stream upTo: Character lf value) equals: #[98].
        self assert: (stream upTo: Character lf) isNil
    ] ensure: [stream close]
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioMalformedLineDoesNotPoisonNextRequest [
	"A parse-error response with null ID cannot consume the next reply."

	| client response constants |

	client := self newStdioInteropClientInMode: #modern.
	client transport sendLine: '{invalid'.
	self assert: (self stdioInteropEcho: 'after-malformed' using: client) equals: 'after-malformed'.
	self assert: client transport responseLines size equals: 3.
	response := self decodeStdioInteropLine: (client transport responseLines at: 2).
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: (response at: 'id') equals: nil.
	self
		assert: ((response at: 'error') at: 'code')
		equals: (constants at: 'McpJsonRpcParseErrorCode')
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioNotificationDoesNotProduceResponse [
	"A following call is a processing barrier for a preceding notification."

	| client requestCount responseCount |

	client := self newStdioInteropClientInMode: #modern.
	requestCount := client transport requestLines size.
	responseCount := client transport responseLines size.
	client sendNotification: 'notifications/initialized' params: EsOrderedDictionary new.
	self
		assert: (self stdioInteropEcho: 'after-notification' using: client)
		equals: 'after-notification'.
	self assert: client transport requestLines size equals: requestCount + 2.
	self assert: client transport responseLines size equals: responseCount + 1
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioProtocolErrorPreservesConnection [
	"An unknown method returns the exact RPC error; later calls succeed."

	| client errorCode constants |

	client := self newStdioInteropClientInMode: #modern.
	errorCode := nil.
	[client sendRequest: 'interop/methodDoesNotExist' params: EsOrderedDictionary new]
		on: McpJsonRpcError
		do: [:error | errorCode := error code].
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: errorCode equals: (constants at: 'McpJsonRpcMethodNotFoundCode').
	self assert: (self stdioInteropEcho: 'after-error' using: client) equals: 'after-error'.
	self assert: client transport responseLines size equals: 3
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioRoundTripsUnicodeAndEscapedText [
	"Unicode, quotes, backslashes and newlines survive a single JSON line."

	| client text request response |

	client := self newStdioInteropClientInMode: #modern.
	text :=
		(UnicodeString utf8:
			#(99 97 102 195 169 32 230 151 165 230 156 172 32 240 159 152 128 32 34 92 9 13 10)
				asByteArray)
					asString.
	self assert: (self stdioInteropEcho: text using: client) asUtf8Bytes equals: text asUtf8Bytes.
	self assert: client transport requestLines size equals: 2.
	self assert: client transport responseLines size equals: 2.
	request := self decodeStdioInteropLine: client transport requestLines last.
	response := self decodeStdioInteropLine: client transport responseLines last.
	self
		assert: (((request at: 'params') at: 'arguments') at: 'text') asUtf8Bytes
		equals: text asUtf8Bytes.
	self assert: (response at: 'id') equals: (request at: 'id')
]

{ #category : 'Testing' }
TestMcpVastInterop >> testVastStdioToolFailurePreservesConnection [
	"A failed tool remains a tool result and does not break later calls."

	| client result |

	client := self newStdioInteropClientInMode: #modern.
	result := client callTool: 'fail' arguments: EsOrderedDictionary new.
	self assert: (result at: 'isError') equals: true.
	self assert: ((result at: 'content') first at: 'text') equals: 'Deliberate stdio tool failure'.
	self assert: (self stdioInteropEcho: 'recovered' using: client) equals: 'recovered'
]
