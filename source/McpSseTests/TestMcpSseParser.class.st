"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpSseParser

`TestMcpSseParser` verifies buffered Server-Sent Events parsing.

## Responsibilities

- Verify multiline data and event-field parsing.
- Verify ID and retry persistence across event blocks.
- Verify comments, unknown fields, and malformed fields are ignored.
- Verify LF, CRLF, CR, and leading byte-order-mark handling.
- Verify only blank-line-terminated events are dispatched.

Tests use in-memory strings and create a fresh stateless parser per operation.
They perform no HTTP requests, background work, or timing-sensitive actions.
"
Class {
	#name : 'TestMcpSseParser',
	#superclass : 'TestCase',
	#category : 'McpSseTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpSseParser >> cr [
	"Answer one carriage-return string."

	^String with: Character cr
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpSseParser >> crlf [
	"Answer one CRLF string."

	^String with: Character cr with: Character lf
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpSseParser >> lf [
	"Answer one line-feed string."

	^String with: Character lf
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpSseParser >> parseLines: lines ending: lineEnding [
	"Parse lines joined by one selected legal SSE line ending."

	| stream |

	stream := WriteStream on: String new.
	lines do: [:line |
		stream
			nextPutAll: line;
			nextPutAll: lineEnding].
	^McpSseParser new parse: stream contents
]

{ #category : 'Parsing' }
TestMcpSseParser >> testByteOrderMarkIsIgnored [
	"One leading Unicode byte-order mark does not alter the first field."

	| bom input events |

	bom := UnicodeString with: (Grapheme value: 16rFEFF).
	input := bom , 'data: value' , self lf , self lf.
	events := McpSseParser new parse: input.
	self assert: events size equals: 1.
	self assert: events first data equals: 'value'
]

{ #category : 'Testing' }
TestMcpSseParser >> testCombiningMarksAfterFieldDelimiterRemainInData [
	"A leading combining acute accent may cluster with the colon or space.
	SSE strips the optional ASCII space, never the following accent."

	| payload input events |

	payload := #[204 129 120].
	#('data:' 'data: ') do: [:prefix |
		input := UnicodeString utf8: (prefix asUtf8Bytes , payload , #[10 10]).
		events := McpSseParser new parse: input.
		self assert: events size equals: 1.
		self assert: events first data asUtf8Bytes equals: payload]
]

{ #category : 'Parsing' }
TestMcpSseParser >> testCommentsAndUnknownFieldsAreIgnored [
	"Comments and unknown fields neither dispatch nor change an event."

	| events |

	events := self parseLines: #(': keep-alive' 'unknown: ignored' 'data: value' '') ending: self lf.
	self assert: events size equals: 1.
	self assert: events first type equals: 'message'.
	self assert: events first data equals: 'value'
]

{ #category : 'Parsing' }
TestMcpSseParser >> testEmptyDataFieldsDispatchEvents [
	"An empty data field dispatches and multiline empty data preserves LF."

	| events |

	events := self parseLines: #('data' '' 'data' 'data:' '') ending: self lf.
	self assert: events size equals: 2.
	self assert: events first data equals: ''.
	self assert: events second data equals: self lf
]

{ #category : 'Parsing' }
TestMcpSseParser >> testEventTypeResetsWhileIdentifierPersists [
	"Event type resets after dispatch while the last event ID persists."

	| events |

	events :=
		self
			parseLines: #('event: update' 'id: event-1' 'data: first' '' 'data: second' '')
			ending: self lf.
	self assert: events size equals: 2.
	self assert: events first type equals: 'update'.
	self assert: events first id equals: 'event-1'.
	self assert: events second type equals: 'message'.
	self assert: events second id equals: 'event-1'
]

{ #category : 'Parsing' }
TestMcpSseParser >> testFieldValueUsesFirstColonAndRemovesAtMostOneSpace [
	"Field parsing splits once and removes at most one leading space."

	| events expected |

	events := self parseLines: #('data:  leading' 'data: value:with:colons' '') ending: self lf.
	expected := ' leading' , self lf , 'value:with:colons'.
	self assert: events size equals: 1.
	self assert: events first data equals: expected
]

{ #category : 'Parsing' }
TestMcpSseParser >> testIdentifierMayBeResetToEmpty [
	"An id field without a value resets the persistent event identifier."

	| events |

	events :=
		self parseLines: #('id: event-1' 'data: first' '' 'id' 'data: second' '') ending: self lf.
	self assert: events size equals: 2.
	self assert: events first id equals: 'event-1'.
	self assert: events second id equals: ''
]

{ #category : 'Parsing' }
TestMcpSseParser >> testInvalidIdentifierAndRetryFieldsAreIgnored [
	"A null ID and nondigit retry value leave prior parser state unchanged."

	| invalidIdentifier lines events |

	invalidIdentifier := 'id: bad' , (String with: (Character value: 0)) , 'value'.
	lines :=
		OrderedCollection new
			add: 'id: valid';
			add: 'retry: 2500';
			add: '';
			add: invalidIdentifier;
			add: 'retry: -1';
			add: 'data: value';
			add: '';
			yourself.
	events := self parseLines: lines ending: self lf.
	self assert: events size equals: 1.
	self assert: events first id equals: 'valid'.
	self assert: events first retry equals: 2500
]

{ #category : 'Parsing' }
TestMcpSseParser >> testLegalLineEndingsProduceEquivalentEvents [
	"LF, CRLF, and CR delimiters produce the same parsed event."

	| endings |

	endings := Array with: self lf with: self crlf with: self cr.
	endings do: [:ending | | events |
		events := self parseLines: #('event: update' 'id: 7' 'data: value' '') ending: ending.
		self assert: events size equals: 1.
		self assert: events first type equals: 'update'.
		self assert: events first id equals: '7'.
		self assert: events first data equals: 'value']
]

{ #category : 'Parsing' }
TestMcpSseParser >> testMultilineDataAndFieldsAreParsed [
	"Data lines join with LF and event, ID, and retry fields are retained."

	| events event expected |

	events :=
		self
			parseLines: #(
				'event: progress' 'id: stream-42' 'retry: 1500' 'data: first' 'data: second' '')
			ending: self lf.
	self assert: events size equals: 1.
	event := events first.
	expected := 'first' , self lf , 'second'.
	self assert: event type equals: 'progress'.
	self assert: event id equals: 'stream-42'.
	self assert: event retry equals: 1500.
	self assert: event data equals: expected
]

{ #category : 'Validation' }
TestMcpSseParser >> testNonStringInputIsRejected [
	"The buffered parser accepts only decoded text."

	self should: [McpSseParser new parse: #[1 2 3]] raise: Error
]

{ #category : 'Parsing' }
TestMcpSseParser >> testOnlyBlankLineTerminatedEventsAreDispatched [
	"A final incomplete event is discarded at end-of-input."

	| events |

	events := self parseLines: #('data: complete' '' 'data: incomplete') ending: self lf.
	self assert: events size equals: 1.
	self assert: events first data equals: 'complete'
]

{ #category : 'Parsing' }
TestMcpSseParser >> testRetryAndIdentifierPersistAcrossBlocksWithoutData [
	"ID and retry fields persist even when their block dispatches no event."

	| events |

	events := self parseLines: #('id: event-9' 'retry: 3000' '' 'data: value' '') ending: self lf.
	self assert: events size equals: 1.
	self assert: events first id equals: 'event-9'.
	self assert: events first retry equals: 3000
]

{ #category : 'Testing' }
TestMcpSseParser >> testUnicodeLineEndingsPreserveFieldsAndDispatch [
	"Exercise decoded UnicodeString input with each legal SSE line ending.
	Check both the first character after a delimiter and the final blank line."

	| payload bytes input events event |

	payload := #[240 159 152 128].
	(Array with: #[10] with: #[13 10] with: #[13]) do: [:ending |
		bytes := 'event: update' asUtf8Bytes , ending ,
			'id: 7' asUtf8Bytes , ending ,
			'retry: 2500' asUtf8Bytes , ending ,
			'data: ' asUtf8Bytes , payload , ending ,
			'data: second' asUtf8Bytes , ending , ending.
		input := UnicodeString utf8: bytes.
		events := McpSseParser new parse: input.
		self assert: events size equals: 1.
		event := events first.
		self assert: event type equals: 'update'.
		self assert: event id equals: '7'.
		self assert: event retry equals: 2500.
		self assert: event data asUtf8Bytes
			equals: payload , #[10] , 'second' asUtf8Bytes]
]

{ #category : 'Testing' }
TestMcpSseParser >> testUnicodeSeparatorsRemainInData [
	"VT, FF, NEL, LS and PS must not split an SSE data line."

	| payload input events |

	payload := #[65 11 66 12 67 194 133 68 226 128 168 69 226 128 169 70].
	input := UnicodeString utf8: ('data: ' asUtf8Bytes , payload , #[10 10]).
	events := McpSseParser new parse: input.
	self assert: events size equals: 1.
	self assert: events first data asUtf8Bytes equals: payload
]
