Class {
	#name : 'TestMcpOAuth2',
	#superclass : 'TestMcpVastInterop',
	#category : 'McpHttpOAuth2TestsApp'
}

{ #category : 'Testing' }
TestMcpOAuth2 class >> shouldInheritSelectors [

	^ false
]

{ #category : 'Integration Tests' }
TestMcpOAuth2 >> testVastClientConnectsToOAuth2ProtectedHttpServer [
	"Live end-to-end: McpOAuth2ProtectedHttpServer with Bearer authentication and RFC 8414 metadata discovery."

	| mcpServer authSettings httpServer client result prmResponse prmUrl |

	mcpServer :=
		McpServer new
			name: 'OAuth2Server';
			version: '1.0.0';
			yourself.
	mcpServer toolRegistry registerTool: (
		McpBlockTool new
			name: 'secure_echo';
			block: ['access granted'];
			yourself).

	authSettings :=
		McpAuthSettings new
			issuerUrl: 'http://127.0.0.1:8960';
			resourceServerUrl: 'http://127.0.0.1:8960/mcp';
			tokenValidator: [:tok | tok = 'test-token' ifTrue: ['valid-user'] ifFalse: [nil]];
			yourself.

	httpServer :=
		McpOAuth2ProtectedHttpServer new
			port: 8960;
			authSettings: authSettings;
			mcpServer: mcpServer;
			start.
	servers add: httpServer.

	client := McpClient modern.
	client transport: (McpHttpClientTransport url: 'http://127.0.0.1:8960/mcp').
	client transport bearerToken: 'test-token'.
	clients add: client.
	client connect.

	result := client callTool: 'secure_echo' arguments: EsOrderedDictionary new.
	self assert: ((result at: 'content') first at: 'text') equals: 'access granted'.

	prmUrl := 'http://127.0.0.1:8960/.well-known/oauth-protected-resource' sstAsUrl.
	prmResponse :=
		(SstHttpClient forTransportScheme: 'httpl')
			get: prmUrl
			typed: nil
			using: nil
			withHeaders: nil.
	self assert: prmResponse header statusCode equals: 200
]
