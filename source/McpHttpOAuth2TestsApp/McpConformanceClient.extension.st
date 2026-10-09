Extension {
	#name : 'McpConformanceClient'
}

{ #category : 'Scenarios' }
McpConformanceClient >> runAuthScenario: aScenarioName [
	"Execute an OAuth2 authenticated scenario using McpOAuth2ClientProvider."

	| authProvider transport mcpClient tools tool resultDict cId cSecret |

	self log: 'Configuring OAuth2 provider for scenario: ' , aScenarioName.
	authProvider := McpOAuth2ClientProvider newForServerUrl: self serverUrl.

	cId := self context at: 'client_id' ifAbsent: [nil].
	cSecret := self context at: 'client_secret' ifAbsent: [nil].
	cId ifNotNil: [authProvider clientId: cId].
	cSecret ifNotNil: [authProvider clientSecret: cSecret].
	(self context at: 'scope' ifAbsent: [nil]) ifNotNil: [:s | authProvider scope: s].

	transport := McpHttpClientTransport url: self serverUrl.
	transport auth: authProvider.

	mcpClient := McpClient new.
	mcpClient mode: #auto.
	mcpClient transport: transport.

	[
		self log: 'Connecting OAuth2 client to ' , self serverUrl.
		mcpClient connect.
		self log: 'Connected. Protocol version: ' , mcpClient protocolVersion printString.

		tools := mcpClient listTools.
		self log: 'Discovered ' , tools size printString , ' tools.'.
		tools notEmpty
			ifTrue: [
				tool := tools first.
				self log: 'Calling tool: ' , (tool at: 'name').
				mcpClient callTool: (tool at: 'name') arguments: EsOrderedDictionary new].

		resultDict :=
			EsOrderedDictionary new
				at: 'status' put: 'SUCCESS';
				at: 'scenario' put: aScenarioName;
				at: 'serverUrl' put: self serverUrl;
				at: 'tools' put: tools;
				yourself.
		^resultDict]
			ensure: [mcpClient close]
]
