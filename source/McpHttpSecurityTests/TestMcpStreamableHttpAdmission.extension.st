Extension {
	#name : 'TestMcpStreamableHttpAdmission'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> requestWithAccept: acceptValue [
	"Answer a POST fixture with acceptValue and a malformed JSON body."

	^(self validRequestWithBody: '{invalid')
		headerAt: 'Accept' put: acceptValue;
		yourself
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testAcceptMediaRangesAllowCaseWhitespaceAndParameters [
	"Exact media types accept case, whitespace, and optional parameters."

	| request body |

	request := self validRequestWithBody: '{invalid'.
	request headerAt: 'Accept' put: ' Text/Event-Stream; q=0.5 , Application/JSON ; charset=utf-8 '.
	body := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self deny: body isEmpty
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testAcceptNearMatchesAreRejected [
	"Media-type prefixes and suffixes cannot satisfy required types."

	| requests |

	requests :=
		OrderedCollection new
			add: (self requestWithAccept: 'application/jsonp, text/event-stream');
			add: (self requestWithAccept: 'application/json, text/event-streaming');
			add: (self requestWithAccept: 'x-application/json, x-text/event-stream');
			yourself.
	requests do: [:request |
		self assert: (transport handlePostRequest: request) equals: ''.
		self assert: request header responseHeader status equals: '400 Bad Request']
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testAcceptWildcardsDoNotReplaceRequiredRepresentations [
	"Wildcards do not explicitly advertise both required MCP media types."

	| wildcardWithJson wildcardOnly |

	wildcardWithJson := self requestWithAccept: '*/*, application/json'.
	wildcardOnly := self requestWithAccept: '*/*'.
	(OrderedCollection new
		add: wildcardWithJson;
		add: wildcardOnly;
		yourself)
			do: [:request |
				self assert: (transport handlePostRequest: request) equals: ''.
				self assert: request header responseHeader status equals: '400 Bad Request']
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testAllowedHostProceeds [
	"Requests with Host matching allowedHosts pass host validation."

	| request |

	transport allowedHosts: #('safe.local').
	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: 'safe.local'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDefaultTransportAcceptsIpv4LoopbackWithAndWithoutPort [
	"A default transport accepts requests with 127.0.0.1 Host header, with and without port."

	| request |

	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: '127.0.0.1'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'.

	request := self requestForMessage: (self pingJsonId: 2).
	request headerAt: 'Host' put: '127.0.0.1:8080'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDefaultTransportAcceptsIpv6LoopbackWithAndWithoutPort [
	"A default transport accepts requests with [::1] Host header, with and without port."

	| request |

	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: '[::1]'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'.

	request := self requestForMessage: (self pingJsonId: 2).
	request headerAt: 'Host' put: '[::1]:8080'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDefaultTransportAcceptsLocalhostWithAndWithoutPort [
	"A default transport accepts requests with localhost Host header, with and without port."

	| request |

	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: 'localhost'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'.

	request := self requestForMessage: (self pingJsonId: 2).
	request headerAt: 'Host' put: 'localhost:8080'.
	transport handlePostRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDefaultTransportRejectsForeignHost [
	"A default transport rejects requests with a foreign Host header with 403 Forbidden."

	| request response |

	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: 'evil.attacker.com'.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'.
	self assert: response isEmpty
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDefaultTransportRejectsForeignHostOnDelete [
	"A default transport rejects DELETE requests with a foreign Host header with 403 Forbidden."

	| exchange session request response |

	exchange := self performInitializationId: 1.
	session := exchange at: 'session'.
	request := self deleteRequestForSession: session.
	request headerAt: 'Host' put: 'evil.attacker.com'.
	response := transport handleDeleteRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'.
	self assert: response isEmpty.
	self assert: (transport sessionNamed: session id ifAbsent: [nil]) notNil
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDefaultTransportRejectsForeignHostWithPort [
	"A default transport rejects requests with a foreign Host header including port with 403 Forbidden."

	| request response |

	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: 'evil.attacker.com:8080'.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'.
	self assert: response isEmpty
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testDisallowedHostReturnsForbidden [
	"Requests with Host header not in allowedHosts are rejected with 403 Forbidden."

	| request response |

	transport allowedHosts: #('safe.local').
	request := self requestForMessage: (self pingJsonId: 1).
	request headerAt: 'Host' put: 'evil.attacker.com'.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'.
	self assert: response isEmpty
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testInvalidAcceptAndContentTypeValuesFailClosed [
	"Non-string HTTP representation fields produce controlled rejection."

	| invalidAccept invalidContentType |

	invalidAccept := self validRequestWithBody: '{invalid'.
	invalidAccept headerAt: 'Accept' put: 1.
	self assert: (transport handlePostRequest: invalidAccept) equals: ''.
	self assert: invalidAccept header responseHeader status equals: '400 Bad Request'.
	invalidContentType := self validRequestWithBody: '{invalid'.
	invalidContentType contentType: 1.
	self assert: (transport handlePostRequest: invalidContentType) equals: ''.
	self assert: invalidContentType header responseHeader status equals: '400 Bad Request'
]

{ #category : 'Authentication' }
TestMcpStreamableHttpAdmission >> testInvalidRequestContextFactoryResultIsRejected [
	"An authentication extension must answer a server request context."

	| exchange session request |

	exchange := self performInitializationId: 100.
	session := exchange at: 'session'.
	transport requestContextFactory: [:incomingRequest :incomingSession | Object new].
	request := self requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 101) session: session.
	self should: [transport handlePostRequest: request] raise: Error.
	self assert: session isInitializing
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testOriginMatchingIgnoresSchemeAndHostCase [
	"HTTP Origin scheme and host comparison is case-insensitive."

	| request body |

	transport allowedOrigins: #('https://app.example:443').
	request := self validRequestWithBody: '{invalid'.
	request headerAt: 'Origin' put: 'HTTPS://APP.EXAMPLE:443'.
	body := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self deny: body isEmpty
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testOriginMatchingIsExact [
	"Origin prefixes, suffixes, and different ports remain forbidden."

	| origins |

	transport allowedOrigins: #('https://app.example:443').
	origins := #('https://app.example' 'https://app.example:444' 'https://app.example.evil:443'
	'https://app.example:443.evil').
	origins do: [:origin | | request |
		request := self validRequestWithBody: '{invalid'.
		request headerAt: 'Origin' put: origin.
		self assert: (transport handlePostRequest: request) equals: ''.
		self assert: request header responseHeader status equals: '403 Forbidden']
]

{ #category : 'Authentication' }
TestMcpStreamableHttpAdmission >> testRequestContextFactoryErrorsPropagateWithoutStateTransition [
	"Authentication failures propagate and cannot mark a session ready."

	| exchange session request |

	exchange := self performInitializationId: 102.
	session := exchange at: 'session'.
	transport requestContextFactory: [:incomingRequest :incomingSession |
		self error: 'Authentication failed'].
	request := self requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 103) session: session.
	self should: [transport handlePostRequest: request] raise: Error.
	self assert: session isInitializing
]
