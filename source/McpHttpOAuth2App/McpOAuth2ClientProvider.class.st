Class {
	#name : 'McpOAuth2ClientProvider',
	#superclass : 'Object',
	#instVars : [
		'serverUrl',
		'clientId',
		'clientSecret',
		'scope',
		'callbackPort',
		'credentials',
		'redirectHandler'
	],
	#pools : [
		'SstConstants',
		'SstHttpConstants'
	],
	#category : 'McpHttpOAuth2App'
}

{ #category : 'Instance Creation' }
McpOAuth2ClientProvider class >> new [
	"Answer a new initialized instance."

	^super new initialize
]

{ #category : 'Instance Creation' }
McpOAuth2ClientProvider class >> newForServerUrl: aStringOrUrl [
	"Create a new OAuth2 client provider for the given server URL.

	 Arguments:
		aStringOrUrl - <String | SstUrl>
	 Answers:
		<McpOAuth2ClientProvider>."

	^self new
		serverUrl: aStringOrUrl;
		yourself
]

{ #category : 'Token Management' }
McpOAuth2ClientProvider >> acquireTokens [
	"Perform full OAuth2 discovery and acquire new credentials."

	| resourceData authServers authServer endpoints tokenEndpoint authEndpoint grantTypes |

	resourceData := self discoverProtectedResourceMetadata.
	authServers :=
		resourceData
			at: 'authorization_servers'
			ifAbsent: [self error: 'Missing authorization_servers in resource metadata'].
	authServers isEmpty ifTrue: [self error: 'No authorization servers found'].
	authServer := authServers first.

	endpoints := self discoverAuthorizationServerMetadata: authServer.
	tokenEndpoint := endpoints at: 'token_endpoint' ifAbsent: [self error: 'Missing token_endpoint'].
	authEndpoint := endpoints at: 'authorization_endpoint' ifAbsent: [nil].
	grantTypes := endpoints at: 'grant_types_supported' ifAbsent: [nil].

	"Direct client credentials grant if supported and configured"
	(self clientSecret notNil and: [
		self clientId notNil and: [
			grantTypes notNil
				ifTrue: [grantTypes includes: 'client_credentials']
				ifFalse: [authEndpoint isNil]]])
					ifTrue: [^self acquireTokensViaClientCredentials: tokenEndpoint].

	"Interactive authorization code grant"
	^self acquireTokensViaAuthorizationCode: authEndpoint tokenEndpoint: tokenEndpoint
]

{ #category : 'Token Management',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> acquireTokensViaAuthorizationCode: authEndpoint tokenEndpoint: tokenEndpoint [
	"Acquire tokens using the interactive OAuth2 Authorization Code grant."

	| redirectUri grant callbackServer authorizationUrl callbackUrl oauthClient scheme |

	authEndpoint ifNil: [self error: 'Missing authorization_endpoint for authorization code grant'].
	redirectUri := 'http://localhost:' , self callbackPort asString , '/callback'.
	grant := SstOAuth2AuthorizationCodeGrant
		newWithClientId: self clientId
		authorizationBaseUrl: authEndpoint sstAsUrl
		tokenUrl: tokenEndpoint sstAsUrl.
	grant scope: self scope; clientSecret: self clientSecret.

	callbackServer := McpOAuth2CallbackServer new.
	callbackServer port: self callbackPort.
	[
		callbackServer start.
		authorizationUrl := grant authorizationUrlWithRedirectTo: redirectUri sstAsUrl state: self randomSecret.
		self redirectHandler value: authorizationUrl.
		callbackUrl := callbackServer waitForCallback.
	] ensure: [
		[(Delay forSeconds: 2) wait. callbackServer stop] fork].

	scheme := tokenEndpoint sstAsUrl localEndpointUrl transport.
	oauthClient := grant
		createClientFromAuthorizationResponseUrl: callbackUrl
		withTransportScheme: scheme.
	credentials := oauthClient oauth2Credentials.
	^credentials
]

{ #category : 'Token Management',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> acquireTokensViaClientCredentials: tokenEndpoint [
	"Acquire tokens using the OAuth2 Client Credentials grant."

	| grant oauthClient |

	grant :=
		SstOAuth2ClientCredentialsGrant
			newWithClientId: self clientId
			tokenUrl: tokenEndpoint sstAsUrl.
	grant clientSecret: self clientSecret.
	self scope ifNotNil: [:s | grant scope: s].
	oauthClient :=
		grant createClientWithTransportScheme: tokenEndpoint sstAsUrl localEndpointUrl transport.
	credentials := oauthClient oauth2Credentials.
	^credentials
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> callbackPort [
	"Answer the port on localhost for receiving the OAuth redirect."

	^callbackPort ifNil: [3030]
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> callbackPort: anInteger [
	"Set the port on localhost for receiving the OAuth redirect.

	 Arguments:
		anInteger - <Integer>."

	callbackPort := anInteger
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> clientId [
	"Answer the OAuth client ID.

	 Answers:
		<String> or nil."

	^clientId
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> clientId: aString [
	"Set the OAuth client ID.

	 Arguments:
		aString - <String>."

	clientId := aString
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> clientSecret [
	"Answer the OAuth client secret.

	 Answers:
		<String> or nil."

	^clientSecret
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> clientSecret: aString [
	"Set the OAuth client secret.

	 Arguments:
		aString - <String>."

	clientSecret := aString
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> credentials [
	"Answer the active OAuth2 credentials, or nil.

	 Answers:
		<SstOAuth2Credentials> or nil."

	^credentials
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> credentials: aSstOAuth2Credentials [
	"Set the active OAuth2 credentials.

	 Arguments:
		aSstOAuth2Credentials - <SstOAuth2Credentials> or nil."

	credentials := aSstOAuth2Credentials
]

{ #category : 'Discovery',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> discoverAuthorizationServerMetadata: authServer [
	"Fetch and parse RFC 8414 authorization server metadata."

	| issuerUri path discoveryPath discoveryUrl scheme response |

	issuerUri := authServer sstAsUrl.
	path := issuerUri path.
	(path isNil or: [path = '/']) ifTrue: [path := ''].
	discoveryPath := '/.well-known/oauth-authorization-server' , path.
	discoveryUrl := (issuerUri scheme , '://' , issuerUri hostport , discoveryPath) sstAsUrl.
	scheme := discoveryUrl localEndpointUrl transport.
	response := (SstHttpClient forTransportScheme: scheme)
		get: discoveryUrl
		typed: nil
		using: nil
		withHeaders: nil.
	response isSstError ifTrue: [self error: 'Failed to discover OAuth endpoints'].
	response header statusCode >= 400
		ifTrue: [self error: 'Failed to discover OAuth endpoints: ' , response header status].
	^McpJSONReader fromString: response contents asString
]

{ #category : 'Discovery',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> discoverProtectedResourceMetadata [
	"Fetch and parse protected resource metadata from the server."

	| metaUrl scheme response |

	metaUrl := self resourceMetadataUrl.
	scheme := metaUrl localEndpointUrl transport.
	response := (SstHttpClient forTransportScheme: scheme)
		get: metaUrl
		typed: nil
		using: nil
		withHeaders: nil.
	response isSstError ifTrue: [self error: 'Failed to fetch resource metadata'].
	response header statusCode >= 400
		ifTrue: [self error: 'Failed to fetch resource metadata: ' , response header status].
	^McpJSONReader fromString: response contents asString
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> initialize [
	"Initialize receiver with default settings."

	super initialize.
	callbackPort := 3030.
	redirectHandler := [:authUrl |
		OsProcessStarter startShell: { 'start'. '"MCP OAuth2 Login"'. '"%1"' bindWith: authUrl asString }]
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> randomSecret [
	"Generate a URL-safe random state secret."

	| generator secret |

	generator := EsSecureRandom new.
	secret := ByteArray new: 32.
	1 to: 32 do: [:index | secret at: index put: (generator nextInt: 255)].
	^Base64CoderUrl current encode: secret
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> redirectHandler [
	"Answer the block used to open the authorization URL."

	^redirectHandler ifNil: [
		redirectHandler := [:authUrl |
			OsProcessStarter startShell: { 'start'. '"MCP OAuth2 Login"'. '"%1"' bindWith: authUrl asString }]]
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> redirectHandler: aBlock [
	"Set the block used to open the authorization URL.

	 Arguments:
		aBlock - <Block> taking an authorization URL string."

	redirectHandler := aBlock
]

{ #category : 'Token Management' }
McpOAuth2ClientProvider >> refreshToken [
	"Refresh the current OAuth2 credentials using the refresh token."

	credentials := credentials refreshWithClientId: self clientId secret: self clientSecret.
	^credentials
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpOAuth2ClientProvider >> resourceMetadataUrl [
	"Answer the RFC 9728 protected resource metadata URL."

	| parsedUrl path |

	self serverUrl ifNil: [self error: 'Server URL is not configured'].
	parsedUrl := self serverUrl sstAsUrl.
	path := parsedUrl path.
	(path isNil or: [path = '/']) ifTrue: [path := ''].
	^(parsedUrl scheme , '://' , parsedUrl hostport , '/.well-known/oauth-protected-resource' , path) sstAsUrl
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> scope [
	"Answer the OAuth scope.

	 Answers:
		<String> or nil."

	^scope
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> scope: aString [
	"Set the OAuth scope.

	 Arguments:
		aString - <String>."

	scope := aString
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> serverUrl [
	"Answer the MCP server endpoint URL string.

	 Answers:
		<String> or nil."

	^serverUrl
]

{ #category : 'Accessing' }
McpOAuth2ClientProvider >> serverUrl: aStringOrUrl [
	"Set the MCP server endpoint URL.

	 Arguments:
		aStringOrUrl - <String | SstUrl>."

	serverUrl := aStringOrUrl ifNotNil: [:u | u asString]
]

{ #category : 'Token Management' }
McpOAuth2ClientProvider >> validAccessToken [
	"Answer a valid Bearer access token string, refreshing or acquiring if necessary."

	(credentials notNil and: [credentials isExpired not and: [credentials accessToken notNil]])
		ifTrue: [^credentials accessToken].
	(credentials notNil and: [credentials canRefresh])
		ifTrue: [
			[self refreshToken.
			^credentials accessToken]
				on: Error
				do: [:ex | credentials := nil]].
	self acquireTokens.
	^credentials ifNotNil: [:c | c accessToken]
]
