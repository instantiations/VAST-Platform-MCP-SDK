Class {
	#name : 'McpHttpServerTransport',
	#superclass : 'Object',
	#instVars : [
		'dispatcher',
		'allowedHosts',
		'allowedOrigins',
		'maximumRequestSize',
		'requestContextFactory',
		'authSettings'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Validation' }
McpHttpServerTransport class >> isLocalhostHost: aHostString [
	"Answer whether aHostString represents a valid localhost host (with or without port)."

	| host hostWithoutPort |

	aHostString isString ifFalse: [^false].
	host := aHostString trimBlanks asLowercase.
	host isEmpty ifTrue: [^false].
	(host = '[::1]' or: [host beginsWithSubCollection: '[::1]:'])
		ifTrue: [hostWithoutPort := '[::1]']
		ifFalse: [
			(host includes: $:)
				ifTrue: [hostWithoutPort := host copyFrom: 1 to: (host indexOf: $:) - 1]
				ifFalse: [hostWithoutPort := host]].
	^#('localhost' '127.0.0.1' '[::1]' '::1') includes: hostWithoutPort
]

{ #category : 'Instance Creation' }
McpHttpServerTransport class >> new [
	"Answer a new initialized server transport.

	 Answers:
		<McpHttpServerTransport>."

	^super new initialize
]

{ #category : 'Accessing' }
McpHttpServerTransport >> allowedHosts [
	"Answer allowed Host header values for DNS rebinding protection.

	 Answers:
		<Set> of <String>."

	allowedHosts ifNil: [allowedHosts := Set new].
	^allowedHosts
]

{ #category : 'Accessing' }
McpHttpServerTransport >> allowedHosts: aCollection [
	"Set allowed Host header values for DNS rebinding protection.

	 Arguments:
		aCollection - <Collection> of <String>.
	 Answers:
		<McpHttpServerTransport> the receiver."

	allowedHosts := aCollection asSet.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTransport >> allowedOrigins [
	"Answer allowed Origin header values.

	 Answers:
		<Set> of <String>."

	allowedOrigins ifNil: [allowedOrigins := Set new].
	^allowedOrigins
]

{ #category : 'Accessing' }
McpHttpServerTransport >> allowedOrigins: aCollection [
	"Set allowed Origin header values.

	 Arguments:
		aCollection - <Collection> of <String>.
	 Answers:
		<McpHttpServerTransport> the receiver."

	allowedOrigins := aCollection asSet.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTransport >> authSettings [
	"Answer the OAuth authentication settings, or nil."

	^authSettings
]

{ #category : 'Configuration' }
McpHttpServerTransport >> authSettings: anAuthSettings [
	"Set the OAuth authentication settings.

	 Arguments:
		anAuthSettings - <McpAuthSettings> or nil.
	 Answers:
		<McpHttpServerTransport> the receiver."

	anAuthSettings ifNotNil: [anAuthSettings validateConfiguration].
	authSettings := anAuthSettings.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTransport >> dispatcher [
	"Answer the JSON-RPC dispatcher.

	 Answers:
		<McpJsonRpcDispatcher> or nil."

	^dispatcher
]

{ #category : 'Accessing' }
McpHttpServerTransport >> dispatcher: anMcpJsonRpcDispatcher [
	"Set the JSON-RPC dispatcher.

	 Arguments:
		anMcpJsonRpcDispatcher - <McpJsonRpcDispatcher>.
	 Answers:
		<McpHttpServerTransport> the receiver."

	dispatcher := anMcpJsonRpcDispatcher.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpServerTransport >> initialize [
	"Initialize shared HTTP server transport defaults.

	 Answers:
		<McpHttpServerTransport> the receiver."

	super initialize.
	allowedOrigins := Set new.
	allowedHosts := Set new.
	maximumRequestSize := 10 * 1024 * 1024.
	^self
]

{ #category : 'Validation' }
McpHttpServerTransport >> isAllowedHost: aHostString [
	"Answer whether aHostString matches the configured allowedHosts, or localhost by default.

	 Arguments:
		aHostString - <String> or nil, HTTP Host header value.
	 Answers:
		<Boolean>."

	| normalizedHost |

	self allowedHosts notEmpty
		ifTrue: [
			(self allowedHosts includes: '*') ifTrue: [^true].
			normalizedHost := aHostString ifNil: [''].
			(self allowedHosts anySatisfy: [:each | each sameAs: normalizedHost]) ifTrue: [^true].
			(normalizedHost beginsWithSubCollection: '[')
				ifTrue: [
					(normalizedHost includesSubstring: ']:')
						ifTrue: [| hostWithoutPort |
							hostWithoutPort := normalizedHost copyFrom: 1 to: (normalizedHost indexOf: $]).
							(self allowedHosts anySatisfy: [:each | each sameAs: hostWithoutPort]) ifTrue: [^true]]]
				ifFalse: [
					(normalizedHost includes: $:)
						ifTrue: [| hostWithoutPort |
							hostWithoutPort := normalizedHost copyFrom: 1 to: (normalizedHost indexOf: $:) - 1.
							(self allowedHosts anySatisfy: [:each | each sameAs: hostWithoutPort]) ifTrue: [^true]]].
			^false].

	^self isLocalhostHost: aHostString
]

{ #category : 'Validation' }
McpHttpServerTransport >> isAllowedOrigin: origin [
	"Answer whether an Origin matches the configured allowlist or a valid localhost origin.

	 HTTP Origin scheme and host names are case-insensitive.

	 Arguments:
		origin - <String> request Origin value.
	 Answers:
		<Boolean>."

	origin ifNil: [^false].
	(allowedOrigins notNil
		and: [
			allowedOrigins notEmpty
				and: [allowedOrigins anySatisfy: [:allowedOrigin | allowedOrigin sameAs: origin]]])
					ifTrue: [^true].
	^self isLocalhostOrigin: origin
]

{ #category : 'Validation' }
McpHttpServerTransport >> isLocalhostHost: aHostString [
	"Answer whether aHostString represents a valid localhost host (with or without port)."

	^self class isLocalhostHost: aHostString
]

{ #category : 'Validation' }
McpHttpServerTransport >> isLocalhostOrigin: anOriginString [
	"Answer whether anOriginString represents a valid localhost origin (HTTP or HTTPS)."

	| origin idx hostport |

	anOriginString isString ifFalse: [^false].
	origin := anOriginString trimBlanks.
	idx := origin indexOfSubCollection: '://' startingAt: 1.
	idx = 0 ifTrue: [^false].
	hostport := origin copyFrom: idx + 3 to: origin size.
	(hostport includes: $/)
		ifTrue: [hostport := hostport copyFrom: 1 to: (hostport indexOf: $/) - 1].
	^self isLocalhostHost: hostport
]

{ #category : 'Accessing' }
McpHttpServerTransport >> maximumRequestSize [
	"Answer maximum allowable request payload size in bytes.

	 Answers:
		<Integer> bytes."

	maximumRequestSize ifNil: [maximumRequestSize := 10 * 1024 * 1024].
	^maximumRequestSize
]

{ #category : 'Accessing' }
McpHttpServerTransport >> maximumRequestSize: anInteger [
	"Set maximum allowable request payload size in bytes.

	 Arguments:
		anInteger - <Integer> positive bytes.
	 Answers:
		<McpHttpServerTransport> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'Maximum request size must be a positive integer'].
	maximumRequestSize := anInteger.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTransport >> requestContextFactory [
	"Answer the optional block building request contexts.

	 Answers:
		<Block> or nil."

	^requestContextFactory
]

{ #category : 'Accessing' }
McpHttpServerTransport >> requestContextFactory: aBlock [
	"Set the optional block building request contexts.

	 Arguments:
		aBlock - <Block> or nil.
	 Answers:
		<McpHttpServerTransport> the receiver."

	requestContextFactory := aBlock.
	^self
]

{ #category : 'Validation' }
McpHttpServerTransport >> validateAuthenticationFor: aRequest [
	"Enforce Bearer authentication when authSettings is configured and enabled.
	 Answers an error response string, or nil when valid.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> or nil."

	| authHeader token principal realm authenticateHeader requiredHeader invalidHeader |

	(self authSettings isNil or: [self authSettings enabled not]) ifTrue: [^nil].

	realm := self authSettings issuerUrl.
	authenticateHeader :=
		realm
			ifNil: ['Bearer']
			ifNotNil: ['Bearer realm="' , realm , '"'].

	requiredHeader :=
		realm
			ifNil: ['Bearer error="invalid_token", error_description="Bearer token required"']
			ifNotNil: [
				authenticateHeader ,
					', error="invalid_token", error_description="Bearer token required"'].

	invalidHeader :=
		realm
			ifNil: ['Bearer error="invalid_token", error_description="Invalid or expired token"']
			ifNotNil: [
				authenticateHeader ,
					', error="invalid_token", error_description="Invalid or expired token"'].

	authHeader := aRequest getHeader: 'Authorization'.
	authHeader ifNil: [authHeader := aRequest getHeader: 'authorization'].
	(authHeader isNil or: [(authHeader beginsWithSubCollection: 'Bearer ') not])
		ifTrue: [
			aRequest header responseHeader
				status: '401 Unauthorized';
				at: 'WWW-Authenticate' put: requiredHeader;
				contentLength: 0.
			^''].

	token := (authHeader copyFrom: 8 to: authHeader size) trimBlanks.
	principal := self authSettings validateToken: token.
	principal ifNil: [
		aRequest header responseHeader
			status: '401 Unauthorized';
			at: 'WWW-Authenticate' put: invalidHeader;
			contentLength: 0.
		^''].

	^nil
]

{ #category : 'Validation' }
McpHttpServerTransport >> validateHostFor: aRequest [
	"Validate the Host header against the configured allowlist or localhost by default per MCP spec.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> error response, or nil when the host is valid."

	| hostHeader |

	hostHeader := aRequest getHeader: 'Host'.
	hostHeader ifNil: [^nil].
	(self isAllowedHost: hostHeader)
		ifFalse: [
			aRequest header responseHeader
				status: '403 Forbidden';
				contentLength: 0.
			^''].
	^nil
]

{ #category : 'Validation' }
McpHttpServerTransport >> validateOriginFor: aRequest [
	"Validate the optional Origin header against the configured allowlist.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> error response, or nil when the origin is valid."

	| origin |

	origin := aRequest getHeader: 'Origin'.
	origin ifNotNil: [
		(self isAllowedOrigin: origin)
			ifFalse: [
				aRequest header responseHeader
					status: '403 Forbidden';
					contentLength: 0.
				^'']].
	^nil
]
