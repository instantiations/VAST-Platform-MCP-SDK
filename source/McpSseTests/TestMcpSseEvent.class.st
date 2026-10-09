"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpSseEvent

`TestMcpSseEvent` verifies the value contract of one parsed SSE event.

## Responsibilities

- Verify default event type, data, identifier, and retry values.
- Verify mutable strings are isolated at assignment and access boundaries.
- Verify event type, identifier, data, and retry validation.

Each test owns one mutable event value. Tests perform no I/O, scheduling, or
shared-state mutation.
"
Class {
	#name : 'TestMcpSseEvent',
	#superclass : 'TestCase',
	#category : 'McpSseTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpSseEvent >> cr [
	"Answer one carriage-return string."

	^String with: Character cr
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpSseEvent >> lf [
	"Answer one line-feed string."

	^String with: Character lf
]

{ #category : 'Initialization' }
TestMcpSseEvent >> testDefaultsDescribeAnEmptyMessageEvent [
	"A new event has the standard message defaults."

	| event |

	event := McpSseEvent new.
	self assert: event type equals: 'message'.
	self assert: event data equals: ''.
	self assert: event id equals: ''.
	self assert: event retry equals: nil
]

{ #category : 'Validation' }
TestMcpSseEvent >> testIdentifierRejectsLineBreaksAndNull [
	"An event identifier must be safe for Last-Event-ID transport."

	| nullIdentifier |

	nullIdentifier := 'prefix' , (String with: (Character value: 0)) , 'suffix'.
	self should: [McpSseEvent new id: 'first' , self lf , 'second'] raise: Error.
	self should: [McpSseEvent new id: 'first' , self cr , 'second'] raise: Error.
	self should: [McpSseEvent new id: nullIdentifier] raise: Error
]

{ #category : 'Validation' }
TestMcpSseEvent >> testRetryAcceptsNilOrNonnegativeInteger [
	"Retry is optional and otherwise a nonnegative millisecond count."

	| event |

	event := McpSseEvent new.
	self assert: (event retry: 0) == event.
	self assert: event retry equals: 0.
	self assert: (event retry: nil) == event.
	self assert: event retry equals: nil.
	self should: [event retry: -1] raise: Error.
	self should: [event retry: 1.5] raise: Error
]

{ #category : 'Validation' }
TestMcpSseEvent >> testStringFieldValidation [
	"Data and identifiers require strings and event type must be nonempty."

	self should: [McpSseEvent new data: 1] raise: Error.
	self should: [McpSseEvent new id: 1] raise: Error.
	self should: [McpSseEvent new type: nil] raise: Error.
	self should: [McpSseEvent new type: ''] raise: Error
]

{ #category : 'Copying' }
TestMcpSseEvent >> testStringFieldsAreDefensivelyCopied [
	"Event string fields are copied when assigned and when accessed."

	| event source returned |

	event := McpSseEvent new.
	source := 'payload' copy.
	event data: source.
	source at: 1 put: $X.
	self assert: event data equals: 'payload'.
	returned := event data.
	returned at: 1 put: $Y.
	self assert: event data equals: 'payload'.
	source := 'update' copy.
	event type: source.
	source at: 1 put: $X.
	self assert: event type equals: 'update'.
	source := 'event-1' copy.
	event id: source.
	source at: 1 put: $X.
	self assert: event id equals: 'event-1'
]
