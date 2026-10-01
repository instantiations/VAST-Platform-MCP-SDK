Class {
	#name : 'McpOAuth2CallbackServer',
	#superclass : 'Object',
	#instVars : [
		'port',
		'server',
		'completionSemaphore',
		'callbackData',
		'timeout'
	],
	#pools : [
		'SstConstants',
		'SstHttpConstants'
	],
	#category : 'McpHttpOAuth2App'
}

{ #category : 'Instance Creation' }
McpOAuth2CallbackServer class >> new [
	"Answer a new initialized instance."

	^super new initialize
]

{ #category : 'Accessing' }
McpOAuth2CallbackServer >> callbackData [
	"Answer the dictionary containing the received query parameters.

	 Answers:
		<Dictionary>."

	^callbackData
]

{ #category : 'Accessing' }
McpOAuth2CallbackServer >> completionSemaphore [
	"Answer the completion semaphore."

	^completionSemaphore ifNil: [completionSemaphore := Semaphore new]
]

{ #category : 'Request Handling',
  #vaVisibility : 'private' }
McpOAuth2CallbackServer >> handleRequest: req response: res [
	"Handle incoming redirect request from the OAuth authorization server."

	| url query params |

	url := req header url.
	(url beginsWithSubCollection: '/callback') ifTrue: [
		query := (url indexOf: $?) > 0
			ifTrue: [url copyFrom: (url indexOf: $?) + 1 to: url size]
			ifFalse: [''].
		params := Dictionary new.
		(query splitOn: '&') do: [:part |
			| key val |
			key := part copyUpTo: $=.
			val := (part indexOf: $=) > 0
				ifTrue: [part copyFrom: (part indexOf: $=) + 1 to: part size]
				ifFalse: [''].
			key notEmpty ifTrue: [
				params
					at: (SstUrlUnicodeEncoder new decode: key useFormUrlEncoding: true)
					put: (SstUrlUnicodeEncoder new decode: val useFormUrlEncoding: true)]].
		callbackData := params.
		self completionSemaphore signal.
		res header: (SstHttpResponseHeader new
			status: SstHttpConstants::HttpOk;
			contentType: 'text/html; charset=utf-8';
			contentLength: 7;
			yourself).
		res contents: 'Success'.
		^res].
	res header: (SstHttpResponseHeader new
		status: SstHttpConstants::HttpNotFound;
		contentLength: 9;
		yourself).
	res contents: 'Not Found'.
	^res
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpOAuth2CallbackServer >> initialize [
	"Initialize the receiver with default settings."

	super initialize.
	port := 3030.
	timeout := 300.
	completionSemaphore := Semaphore new.
	callbackData := Dictionary new
]

{ #category : 'Testing' }
McpOAuth2CallbackServer >> isRunning [
	"Answer true if the callback server is active and running."

	^server notNil and: [server isRunning]
]

{ #category : 'Accessing' }
McpOAuth2CallbackServer >> port [
	"Answer the port the local callback server listens on.

	 Answers:
		<Integer>."

	^port
]

{ #category : 'Accessing' }
McpOAuth2CallbackServer >> port: anInteger [
	"Set the port the local callback server listens on.

	 Arguments:
		anInteger - <Integer>."

	port := anInteger
]

{ #category : 'Lifecycle' }
McpOAuth2CallbackServer >> start [
	"Start the transient local HTTP callback server."

	| handler result |

	self stop.
	server := SstBasicServer new.
	handler := DirectedMessage
		receiver: [:req :res | self handleRequest: req response: res]
		selector: #value:value:.
	(result := server addHandlerUrl: 'http://:' , self port asString) isSstError ifTrue: [result raise].
	server requestHandler: handler.
	(result := server startUp) isSstError ifTrue: [result raise]
]

{ #category : 'Lifecycle' }
McpOAuth2CallbackServer >> stop [
	"Stop and shut down the callback server."

	server ifNotNil: [
		server shutDown.
		server := nil]
]

{ #category : 'Accessing' }
McpOAuth2CallbackServer >> timeout [
	"Answer the callback timeout in seconds.

	 Answers:
		<Integer>."

	^timeout
]

{ #category : 'Accessing' }
McpOAuth2CallbackServer >> timeout: anInteger [
	"Set the callback timeout in seconds.

	 Arguments:
		anInteger - <Integer>."

	timeout := anInteger
]

{ #category : 'Lifecycle' }
McpOAuth2CallbackServer >> waitForCallback [
	"Wait for the OAuth callback and return the response data dictionary."

	| delay timedOut |

	timedOut := false.
	delay := [(Delay forSeconds: self timeout) wait. timedOut := true. self completionSemaphore signal] fork.
	self completionSemaphore sstWait.
	delay terminate.
	timedOut ifTrue: [
		self stop.
		self error: 'Timeout waiting for OAuth callback'].
	(self callbackData includesKey: 'error') ifTrue: [
		| err |
		err := self callbackData at: 'error_description' ifAbsent: [self callbackData at: 'error'].
		self error: 'OAuth authorization error: ' , err].
	^self callbackData
]
