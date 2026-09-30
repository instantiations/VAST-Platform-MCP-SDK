Class {
	#name : 'McpOAuth2ClientTransport',
	#superclass : 'McpHttpClientTransport',
	#instVars : [
		'clientId',
		'clientSecret',
		'scope',
		'localHttpServerPort',
		'oauthCredentials'
	],
	#pools : [
		'SstConstants',
		'SstErrorConstants'
	],
	#category : 'McpHttpOAuth2App'
}

{ #category : 'Private',
  #vaVisibility : 'private' }
McpOAuth2ClientTransport >> acquireTokenForResourceMetadata: resourceMetadataUrl [
	| resourceResponse resourceData authServers authServer issuerUri path discoveryPath discoveryUrl discoveryResponse endpoints authEndpoint tokenEndpoint grant server handler result redirectUri authorizationUrl completionSemaphore |
	
	"1. Resource Metadata Discovery"
	resourceResponse := (SstHttpClient  forTransportScheme: 'httpsl') get: resourceMetadataUrl sstAsUrl typed: nil using: nil withHeaders: nil.
	resourceResponse isSstError ifTrue: [self error: 'Failed to fetch resource metadata'].
	resourceResponse header statusCode >= 400 ifTrue: [self error: 'Failed to fetch resource metadata: ', resourceResponse header status].
	resourceData := McpJSONReader fromString: resourceResponse contents asString.
	authServers := resourceData at: 'authorization_servers' ifAbsent: [self error: 'Missing authorization_servers in resource metadata'].
	authServers isEmpty ifTrue: [self error: 'No authorization servers found'].
	authServer := authServers first.
	
	"2. Authorization Server Discovery"
	issuerUri := authServer sstAsUrl.
	path := issuerUri path.
	(path isNil or: [path = '/']) ifTrue: [path := ''].
	discoveryPath := '/.well-known/oauth-authorization-server', path.
	discoveryUrl := (issuerUri scheme, '://', issuerUri hostport, discoveryPath) sstAsUrl.
	
	discoveryResponse := (SstHttpClient  forTransportScheme: 'httpsl') get: discoveryUrl typed: nil using: nil withHeaders: nil.
	discoveryResponse isSstError ifTrue: [self error: 'Failed to discover OAuth endpoints'].
	discoveryResponse header statusCode >= 400 ifTrue: [self error: 'Failed to discover OAuth endpoints: ', discoveryResponse header status].
	endpoints := McpJSONReader fromString: discoveryResponse contents asString.
	authEndpoint := endpoints at: 'authorization_endpoint' ifAbsent: [self error: 'Missing authorization_endpoint'].
	tokenEndpoint := endpoints at: 'token_endpoint' ifAbsent: [self error: 'Missing token_endpoint'].
	
	"3. Setup Flow"
	redirectUri := 'http://localhost:', self localHttpServerPort asString, '/callback'.
	grant := SstOAuth2AuthorizationCodeGrant newWithClientId: self clientId authorizationBaseUrl: authEndpoint sstAsUrl tokenUrl: tokenEndpoint sstAsUrl.
	grant scope: self scope; clientSecret: self clientSecret.
	
	"4. Setup HTTP Listener"
	completionSemaphore := Semaphore new.
	server := SstBasicServer new.
	handler := DirectedMessage receiver: [:req :res |
		(req header url beginsWithSubCollection: '/callback') ifTrue: [
			[
				| oauthClient |
				oauthClient := grant createClientFromAuthorizationResponseUrl: (redirectUri, req header url) sstAsUrl.
				oauthCredentials := oauthClient oauth2Credentials.
				completionSemaphore signal.
				(Delay forSeconds: 1) wait. 
				server shutDown
			] fork
		].
		res header: (SstHttpResponseHeader new status: SstHttpConstants::HttpOk; contentLength: 12; yourself); contents: 'Success'.
	] selector: #value:value:.
	(result := server addHandlerUrl: 'http://:', self localHttpServerPort asString) isSstError ifTrue: [result raise].
	server requestHandler: handler.
	(result := server startUp) isSstError ifTrue: [result raise].
	
	"5. Launch Browser and Wait"
	authorizationUrl := grant authorizationUrlWithRedirectTo: redirectUri sstAsUrl state: self randomSecret.
	OsProcessStarter startShell: { 'start'. '"MCP OAuth2 Login"'. '"%1"' bindWith: authorizationUrl asString }.
	completionSemaphore wait.
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> clientId [
	^clientId
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> clientId: aString [
	clientId := aString
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> clientSecret [
	^clientSecret
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> clientSecret: aString [
	clientSecret := aString
]

{ #category : 'Execution',
  #vaVisibility : 'private' }
McpOAuth2ClientTransport >> doSendRequest: requestDictionary id: requestId headers: requestHeaders [
	"Send a request using a fresh SST exchange. Intercepts 401s, attempts OAuth2 flow, and retries."

	| result |
	
	[result := super doSendRequest: requestDictionary id: requestId headers: requestHeaders]
		when: ExSstNonFatalError
		do: [:signal | 
			| sstError response header statusCode resourceMetadataUrl authenticateHeader |
			sstError := signal arguments second.
				response := sstError errorObject.
				(response isKindOf: SstCommunicationMessage) ifTrue: [
					header := response header.
					statusCode := header statusCode.
					statusCode = 401 ifTrue: [
						authenticateHeader := header at: 'WWW-Authenticate' ifAbsent: [nil].
						authenticateHeader ifNotNil: [
							resourceMetadataUrl := self extractResourceMetadataUrlFrom: authenticateHeader.
							resourceMetadataUrl ifNotNil: [
								self acquireTokenForResourceMetadata: resourceMetadataUrl.
								"Retry"
								^super doSendRequest: requestDictionary id: requestId headers: requestHeaders
						]
					]
				]
			].
			sstError raise
		].
	^result
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpOAuth2ClientTransport >> extractResourceMetadataUrlFrom: authenticateHeaderString [
	| marker startIdx endIdx |
	marker := 'resource_metadata="'.
	startIdx := authenticateHeaderString indexOfSubCollection: marker startingAt: 1.
	startIdx = 0 ifTrue: [^nil].
	startIdx := startIdx + marker size.
	endIdx := authenticateHeaderString indexOf: $" startingAt: startIdx.
	endIdx = 0 ifTrue: [^nil].
	^authenticateHeaderString copyFrom: startIdx to: endIdx - 1
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpOAuth2ClientTransport >> initialize [
	super initialize.
	self tokenProvider: [
		oauthCredentials ifNotNil: [
			oauthCredentials canRefresh ifTrue: [
				oauthCredentials := oauthCredentials refreshWithClientId: self clientId secret: self clientSecret].
			oauthCredentials accessToken]
		ifNil: [nil]].
	^self
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> localHttpServerPort [
	^localHttpServerPort ifNil: [9999]
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> localHttpServerPort: anInteger [
	localHttpServerPort := anInteger
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> oauthCredentials [
	^oauthCredentials
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpOAuth2ClientTransport >> randomSecret [
	| generator secret |
	generator := EsSecureRandom new.
	secret := ByteArray new: 32.
	1 to: 32 do: [:index | secret at: index put: (generator nextInt: 255)].
	^Base64CoderUrl current encode: secret
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> scope [
	^scope
]

{ #category : 'Accessing' }
McpOAuth2ClientTransport >> scope: aString [
	scope := aString
]
