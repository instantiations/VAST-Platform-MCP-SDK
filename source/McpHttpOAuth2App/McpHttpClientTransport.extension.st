Extension {
	#name : 'McpHttpClientTransport'
}

{ #category : 'Configuration' }
McpHttpClientTransport >> auth: anOAuth2ClientProvider [
	"Configure this transport to use an OAuth2 client provider for dynamic token authorization.

	 Arguments:
		anOAuth2ClientProvider - <McpOAuth2ClientProvider>
	 Answers:
		<McpHttpClientTransport> the receiver."

	anOAuth2ClientProvider serverUrl ifNil: [
		self url ifNotNil: [:u | anOAuth2ClientProvider serverUrl: u]].
	self tokenProvider: [anOAuth2ClientProvider validAccessToken].
	^self
]
