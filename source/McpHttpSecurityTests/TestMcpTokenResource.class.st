"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Deterministic, self-contained MCP 2.2.0 regression tests.
Fixtures own their state and do not contact external services.
"
Class {
	#name : 'TestMcpTokenResource',
	#superclass : 'TestCase',
	#category : 'McpHttpSecurityTests'
}

{ #category : 'Testing' }
TestMcpTokenResource >> testEnabledValidationRequiresResourceUrl [
	"Fail before token use when no resource URL is supplied."
	| settings |
	settings := McpAuthSettings new validateTokenResource: true; yourself.
	self should: [settings validateConfiguration] raise: Error

]

{ #category : 'Testing' }
TestMcpTokenResource >> testPrestartSettingsReachBothTransports [
	"Preconfigured settings reach both HTTP services."
	| host settings |
	settings := McpAuthSettings new
		resourceServerUrl: 'https://example.com/mcp';
		validateTokenResource: true; yourself.
	host := McpHttpServer new mcpServer: McpServer new;
		authSettings: settings; sessionIdleTimeout: 25; maxSessions: 7;
			yourself.
	self assert: host transport authSettings == settings.
	self assert: host sseTransport authSettings == settings.
	self assert: host transport sessionIdleTimeout equals: 25.
	self assert: host transport maxSessions equals: 7.
	host stop

]

{ #category : 'Testing' }
TestMcpTokenResource >> testResourceMatchesNormalizedOriginAndTrailingSlash [
	"A verified resource accepts equivalent host, port and terminal slash."
	| settings principal |
	principal := Dictionary with: 'resource' -> 'https://EXAMPLE.com:443/mcp/'.
	settings := McpAuthSettings new
		resourceServerUrl: 'https://example.com/mcp';
		validateTokenResource: true;
		tokenValidator: [:token | principal]; yourself.
	self assert: (settings validateToken: 'signed-token') == principal

]

{ #category : 'Testing' }
TestMcpTokenResource >> testResourcePathAndQueryRemainSignificant [
	"Resource checks preserve path case, query, scheme and nondefault port."
	| settings principal |
	settings := McpAuthSettings new
		resourceServerUrl: 'https://example.com/mcp';
		validateTokenResource: true;
		tokenValidator: [:token | principal]; yourself.
	#('https://example.com/MCP' 'https://example.com/mcp?tenant=other'
		'https://example.com:444/mcp' 'http://example.com/mcp') do: [:resource |
			principal := Dictionary with: 'resource' -> resource.
			self assert: (settings validateToken: 'token') isNil]

]

{ #category : 'Testing' }
TestMcpTokenResource >> testUnspecifiedValidationWarnsOnceAndPreservesTwoXDefault [
	"The 2.x default stays disabled and emits a nonblocking notification."
	| settings notices |
	notices := 0.
	settings := McpAuthSettings new
		resourceServerUrl: 'https://example.com/mcp'; yourself.
	[
		self assert: (settings validateToken: 'token') equals: 'token'.
		self assert: (settings validateToken: 'token') equals: 'token'
	] on: McpDeprecationWarning do: [:warning |
		notices := notices + 1. warning resume].
	self assert: notices equals: 1

]

{ #category : 'Testing' }
TestMcpTokenResource >> testWrongMissingAndUnverifiedResourceRejected [
	"Never infer a resource from an opaque token or a missing claim."
	| settings principal |
	settings := McpAuthSettings new
		resourceServerUrl: 'https://example.com/mcp';
		validateTokenResource: true;
		tokenValidator: [:token | principal]; yourself.
	principal := Dictionary with: 'resource' -> 'https://other.example/mcp'.
	self assert: (settings validateToken: 'token') isNil.
	principal := Dictionary new.
	self assert: (settings validateToken: 'token') isNil.
	principal := 'opaque-principal'.
	self assert: (settings validateToken: 'token') isNil.
	settings tokenValidator: nil.
	self assert: (settings validateToken: 'token') isNil

]
