Class {
	#name : 'TestMcpBearerAuth',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'transport',
		'authSettings'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpSecurityTests'
}

{ #category : 'Testing' }
TestMcpBearerAuth >> setUp [
	"Prepare server, transport, and configured auth settings."

	super setUp.
	server := McpServer new.
	transport :=
		McpStreamableHttpTransport new
			dispatcher: (
				McpJsonRpcDispatcher new
					server: server;
					yourself);
			yourself.
	authSettings :=
		McpAuthSettings new
			issuerUrl: 'https://auth.example.com';
			validateTokenResource: false;
			resourceServerUrl: 'http://127.0.0.1:8080/mcp';
			requiredScopes: #('tools:call');
			tokenValidator: [:tok | tok = 'valid-secret-token' ifTrue:
				['user-123'] ifFalse: [nil]];
			yourself.
	transport authSettings: authSettings

]

{ #category : 'Running' }
TestMcpBearerAuth >> tearDown [
	"Clean up."

	super tearDown
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testAuthorizationServerMetadata [
	"Verify RFC 8414 metadata format and URLs."

	| meta |

	meta := authSettings authorizationServerMetadata.
	self assert: (meta at: 'issuer') equals: 'https://auth.example.com'.
	self assert: (meta at: 'token_endpoint') equals: 'https://auth.example.com/oauth/token'.
	self
		assert: (meta at: 'authorization_endpoint')
		equals: 'https://auth.example.com/oauth/authorize'.
	self assert: (meta includesKey: 'grant_types_supported')
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testClientTransportDynamicTokenProvider [
	"Verify McpHttpClientTransport dynamically evaluates tokenProvider when configured."

	| clientTransport headers counter |

	counter := 0.
	clientTransport := McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp'.
	clientTransport tokenProvider: [
		counter := counter + 1.
		'token-' , counter printString].
	headers := clientTransport buildHeaders.

	self assert: (headers at: 'Authorization') equals: 'Bearer token-1'.
	self assert: counter equals: 1
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testClientTransportInjectsBearerToken [
	"Verify McpHttpClientTransport populates Authorization header when bearerToken is configured."

	| clientTransport headers |

	clientTransport := McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp'.
	clientTransport bearerToken: 'my-jwt-token'.
	headers := clientTransport buildHeaders.

	self assert: (headers at: 'Authorization') equals: 'Bearer my-jwt-token'
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testDeleteRequiresValidResourceWhenEnabled [
	"Session deletion uses the same resource-aware authentication boundary."
	| request |
	authSettings validateTokenResource: true;
		tokenValidator: [:token | Dictionary new].
	request := McpHttpServerTestRequest new
		headerAt: 'Authorization' put: 'Bearer valid-secret-token'; yourself.
	transport handleDeleteRequest: request.
	self assert: request header responseHeader status equals: '401 Unauthorized'

]

{ #category : 'Testing' }
TestMcpBearerAuth >> testDisabledAuthAllowsUnauthenticatedRequests [
	"Verify requests proceed when authSettings is disabled."

	| request body result |

	authSettings enabled: false.
	body :=
		'{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'.
	request :=
		McpHttpServerTestRequest new
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'server/discover';
			headerAt: 'Accept' put: 'application/json';
			contentType: 'application/json';
			contents: body asUtf8Bytes;
			yourself.
	result := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '200 OK'
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testInvalidTokenReturns401 [
	"Verify requests with invalid bearer token receive 401 Unauthorized."

	| request body |

	body := '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}'.
	request :=
		McpHttpServerTestRequest new
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Accept' put: 'application/json';
			headerAt: 'Authorization' put: 'Bearer wrong-token';
			contentType: 'application/json';
			contents: body asUtf8Bytes;
			yourself.
	transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '401 Unauthorized'.
	self assert: (request header responseHeader at: 'WWW-Authenticate' ifAbsent: [nil]) notNil
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testMissingAuthorizationHeaderReturns401 [
	"Verify requests without Authorization header receive 401 Unauthorized."

	| request body |

	body := '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}'.
	request :=
		McpHttpServerTestRequest new
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Accept' put: 'application/json';
			contentType: 'application/json';
			contents: body asUtf8Bytes;
			yourself.
	transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '401 Unauthorized'.
	self assert: (request header responseHeader at: 'WWW-Authenticate' ifAbsent: [nil]) notNil
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testProtectedResourceMetadata [
	"Verify OAuth protected resource metadata."

	| meta |

	meta := authSettings protectedResourceMetadata.
	self assert: (meta at: 'resource') equals: 'http://127.0.0.1:8080/mcp'.
	self assert: (meta at: 'authorization_servers') equals: #('https://auth.example.com').
	self assert: (meta at: 'scopes_supported') equals: #('tools:call')
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testValidTokenProceeds [
	"Verify requests with valid bearer token succeed."

	| request body result |

	body :=
		'{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'.
	request :=
		McpHttpServerTestRequest new
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'server/discover';
			headerAt: 'Accept' put: 'application/json';
			headerAt: 'Authorization' put: 'Bearer valid-secret-token';
			contentType: 'application/json';
			contents: body asUtf8Bytes;
			yourself.
	result := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '200 OK'.
	self assert: (result includesSubstring: '"resultType":"complete"')
]

{ #category : 'Testing' }
TestMcpBearerAuth >> testWrongResourceIsRejectedAtHttpBoundary [
	"The HTTP POST endpoint returns 401 for another resource's verified token."
	| request |
	authSettings validateTokenResource: true;
		tokenValidator: [:token |
			Dictionary with: 'resource' -> 'https://other.example/mcp'].
	request := McpHttpServerTestRequest new
		headerAt: 'Authorization' put: 'Bearer valid-secret-token';
		headerAt: 'Accept' put: 'application/json, text/event-stream';
		contentType: 'application/json';
		contents: '{"jsonrpc":"2.0","id":1,"method":"ping"}' asUtf8Bytes;
		yourself.
	transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '401 Unauthorized'

]
