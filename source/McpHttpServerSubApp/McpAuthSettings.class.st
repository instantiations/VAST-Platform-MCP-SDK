"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpAuthSettings

`McpAuthSettings` configures OAuth 2.0 / OIDC Bearer authentication and metadata
discovery for MCP HTTP transports.

## Responsibilities

- Configure issuer URL, resource server URL, and required OAuth scopes.
- Validate Bearer tokens via `tokenValidator` blocks (`validateToken:`).
- Generate RFC 8414 OAuth 2.0 Authorization Server Metadata (`authorizationServerMetadata`).
- Generate RFC 9207 OAuth 2.0 Protected Resource Metadata (`protectedResourceMetadata`).
- Toggle authentication enforcement via `enabled`.

## Lifecycle and boundaries

Owned by `McpHttpServer` or its transports.
"
Class {
	#name : 'McpAuthSettings',
	#superclass : 'Object',
	#instVars : [
		'issuerUrl',
		'resourceServerUrl',
		'requiredScopes',
		'tokenValidator',
		'enabled',
		'validateTokenResource',
		'resourceWarningIssued'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Instance Creation' }
McpAuthSettings class >> new [
	"Answer a new initialized auth settings instance.

	 Answers:
		<McpAuthSettings>."

	^super new initialize
]

{ #category : 'Metadata' }
McpAuthSettings >> authorizationServerMetadata [
	"Answer RFC 8414 Authorization Server Metadata.

	 Answers:
		<KeyedCollection>."

	| meta iss |

	iss := self issuerUrl ifNil: ['http://localhost:8080'].
	meta :=
		EsOrderedDictionary new
			at: 'issuer' put: iss;
			at: 'authorization_endpoint' put: iss , '/oauth/authorize';
			at: 'token_endpoint' put: iss , '/oauth/token';
			at: 'response_types_supported' put: #('code');
			at: 'grant_types_supported'
				put: #('authorization_code' 'refresh_token' 'client_credentials');
			at: 'token_endpoint_auth_methods_supported' put: #('client_secret_post' 'none');
			yourself.
	^meta
]

{ #category : 'Accessing' }
McpAuthSettings >> enabled [
	"Answer whether Bearer authentication enforcement is active.

	 Answers:
		<Boolean>."

	enabled ifNil: [enabled := true].
	^enabled
]

{ #category : 'Accessing' }
McpAuthSettings >> enabled: aBoolean [
	"Set whether Bearer authentication enforcement is active.

	 Arguments:
		aBoolean - <Boolean>.
	 Answers:
		<McpAuthSettings> the receiver."

	enabled := aBoolean.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpAuthSettings >> initialize [
	"Initialize auth settings defaults."

	super initialize.
	enabled := true.
	requiredScopes := #().
	^self
]

{ #category : 'Accessing' }
McpAuthSettings >> issuerUrl [
	"Answer the OAuth authorization server issuer URL.

	 Answers:
		<String> or nil."

	^issuerUrl
]

{ #category : 'Accessing' }
McpAuthSettings >> issuerUrl: aUrlString [
	"Set the OAuth authorization server issuer URL.

	 Arguments:
		aUrlString - <String>.
	 Answers:
		<McpAuthSettings> the receiver."

	issuerUrl := aUrlString copy.
	^self
]

{ #category : 'Metadata' }
McpAuthSettings >> protectedResourceMetadata [
	"Answer OAuth 2.0 Protected Resource Metadata (RFC 9207 / RFC 8414).

	 Answers:
		<KeyedCollection>."

	| meta res iss |

	res := self resourceServerUrl ifNil: ['http://localhost:8080/mcp'].
	iss := self issuerUrl ifNil: ['http://localhost:8080'].
	meta :=
		EsOrderedDictionary new
			at: 'resource' put: res;
			at: 'authorization_servers' put: (Array with: iss);
			yourself.
	self requiredScopes notEmpty ifTrue: [meta at: 'scopes_supported' put: self requiredScopes].
	^meta
]

{ #category : 'Accessing' }
McpAuthSettings >> requiredScopes [
	"Answer the required OAuth scopes for accessing this MCP server.

	 Answers:
		<Collection> of <String>."

	requiredScopes ifNil: [requiredScopes := #()].
	^requiredScopes
]

{ #category : 'Accessing' }
McpAuthSettings >> requiredScopes: aCollection [
	"Set the required OAuth scopes for accessing this MCP server.

	 Arguments:
		aCollection - <Collection> of <String>.
	 Answers:
		<McpAuthSettings> the receiver."

	requiredScopes := aCollection asArray.
	^self
]

{ #category : 'Accessing' }
McpAuthSettings >> resourceServerUrl [
	"Answer the MCP resource server identifier URL.

	 Answers:
		<String> or nil."

	^resourceServerUrl
]

{ #category : 'Accessing' }
McpAuthSettings >> resourceServerUrl: aUrlString [
	"Set the MCP resource server identifier URL.

	 Arguments:
		aUrlString - <String>.
	 Answers:
		<McpAuthSettings> the receiver."

	resourceServerUrl := aUrlString copy.
	^self
]

{ #category : 'Accessing' }
McpAuthSettings >> tokenValidator [
	"Answer the token validation block [:tokenString | ...].

	 Answers:
		<Block> or nil."

	^tokenValidator
]

{ #category : 'Accessing' }
McpAuthSettings >> tokenValidator: aBlock [
	"Set the token validation block [:tokenString | ...].

	 Arguments:
		aBlock - <Block>.
	 Answers:
		<McpAuthSettings> the receiver."

	tokenValidator := aBlock.
	^self
]

{ #category : 'Validation' }
McpAuthSettings >> validateConfiguration [
	"Validate the completed configuration when attached or used.
	Answers:
		<McpAuthSettings> the receiver.
	Raises:
		<Error> resource validation enabled without a valid resource URL.
		<McpDeprecationWarning> unspecified 2.x resource policy, once."
	validateTokenResource == true ifTrue: [
		(McpHttpUrlPolicy resourceKey: resourceServerUrl) ifNil: [
			self error:
				'validateTokenResource requires a valid resourceServerUrl']].
	(validateTokenResource isNil and: [resourceServerUrl notNil and: [
		resourceWarningIssued ~= true]]) ifTrue: [
			resourceWarningIssued := true.
			McpDeprecationWarning signal:
				'Set validateTokenResource; the 3.0 default will be true']

]

{ #category : 'Validation' }
McpAuthSettings >> validateToken: aTokenString [
	"Validate the token, then optionally enforce its verified resource.
	The validator must supply a keyed principal with a textual 'resource'.
	This method never decodes an unverified token to infer its audience.
	Arguments:
		aTokenString - <String> bearer token.
	Answers:
		<Object | nil> verified principal, or nil when rejected."
	| principal expected actual |
	self validateConfiguration.
	principal := self tokenValidator
		ifNotNil: [:validator |
			[validator cull: aTokenString] on: Error do: [:failure | nil]]
		ifNil: [
			(aTokenString isString and: [aTokenString isEmpty not])
				ifTrue: [aTokenString] ifFalse: [nil]].
	principal ifNil: [^nil].
	validateTokenResource == true ifFalse: [^principal].
	(principal isKindOf: KeyedCollection) ifFalse: [^nil].
	expected := McpHttpUrlPolicy resourceKey: resourceServerUrl.
	actual := McpHttpUrlPolicy resourceKey:
		(principal at: 'resource' ifAbsent: [nil]).
	(actual notNil and: [actual = expected]) ifTrue: [^principal].
	^nil

]

{ #category : 'Accessing' }
McpAuthSettings >> validateTokenResource [
	"Answer nil when unspecified, false when delegated, or true to enforce.
	Answers:
		<Boolean | nil> resource-validation setting."
	^validateTokenResource

]

{ #category : 'Accessing' }
McpAuthSettings >> validateTokenResource: aBoolean [
	"Choose whether to require the verifier's resource to match this server.
	Arguments:
		aBoolean - <Boolean | nil>; nil keeps the 2.x default disabled.
	Answers:
		<McpAuthSettings> the receiver."
	(aBoolean isNil or: [aBoolean isBoolean])
		ifFalse: [self error:
			'Token resource validation must be boolean or nil'].
	validateTokenResource := aBoolean.
	resourceWarningIssued := false

]
