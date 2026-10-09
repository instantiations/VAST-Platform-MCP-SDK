"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSseParser

`McpSseParser` decodes finite Server-Sent Event text for MCP HTTP responses.

## Responsibilities

- Recognize standard SSE fields, line endings, comments, and dispatch.
- Ignore one leading Unicode byte-order mark without changing data.

## Lifecycle and boundaries

Parser calls are independent and retain no stream resources.
"
Class {
	#name : 'McpSseParser',
	#superclass : 'Object',
	#category : 'McpHttpClientSubApp'
}

{ #category : 'Dispatching',
  #vaVisibility : 'private' }
McpSseParser >> dispatchData: dataString type: eventType id: identifier retry: retryValue into: events [
	"Append one completed event when the SSE data buffer is nonempty.

	 Arguments:
		dataString - <String> LF-terminated data buffer.
		eventType - <String> explicit event type, or empty.
		identifier - <String> current last-event identifier.
		retryValue - <Integer> current retry delay, or nil.
		events - <OrderedCollection> output collection.
	 Answers:
		<McpSseParser> the receiver."

	| event |

	dataString isEmpty ifTrue: [^self].
	event :=
		McpSseEvent new
			type: (eventType isEmpty ifTrue: ['message'] ifFalse: [eventType]);
			data: dataString allButLast;
			id: identifier;
			retry: retryValue;
			yourself.
	events add: event.
	^self
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpSseParser >> isAsciiDigit: aCharacter [
	"Answer whether a character is an ASCII decimal digit.

	 Arguments:
		aCharacter - <Character> candidate.
	 Answers:
		<Boolean>."

	^aCharacter codePoint between: $0 codePoint and: $9 codePoint
]

{ #category : 'Parsing' }
McpSseParser >> parse: responseString [
	"Parse a complete buffered SSE entity supplied as decoded text.
	Recognize protocol delimiters as UTF-8 bytes, not grapheme indices.
	In a UnicodeString CRLF is one grapheme; String crlf has size two.
	Unicode nextLine also recognizes separators that are data in SSE.

	Arguments:
		responseString - <String> complete decoded SSE response text.
	Answers:
		<Array> parsed McpSseEvent instances."

	| normalized stream events line colonIndex field value valueBytes
	  eventType data identifier retry lf |

	responseString isString ifFalse: [self error: 'SSE response must be a string'].
	normalized := responseString asUtf8Bytes.
	normalized := normalized copyReplaceAll: #[13 10] with: #[10].
	normalized := normalized copyReplaceAll: #[13] with: #[10].
	(normalized size >= 3 and: [
		(normalized copyFrom: 1 to: 3) = #[239 187 191]]) ifTrue: [
			normalized := normalized size = 3
				ifTrue: [#[]]
				ifFalse: [normalized copyFrom: 4 to: normalized size]].
	stream := normalized readStream.
	lf := String with: Character lf.
	events := OrderedCollection new.
	eventType := ''.
	data := ''.
	identifier := ''.
	retry := nil.
	[stream atEnd] whileFalse: [
		line := stream upTo: 10.
		line isEmpty
			ifTrue: [
				self dispatchData: data type: eventType id: identifier
					retry: retry into: events.
				eventType := ''.
				data := '']
			ifFalse: [
				line first = 58 ifFalse: [
					colonIndex := line indexOf: 58.
					colonIndex = 0
						ifTrue: [
							field := line asString.
							valueBytes := #[]]
						ifFalse: [
							field := (line copyFrom: 1 to: colonIndex - 1) asString.
							valueBytes := colonIndex = line size
								ifTrue: [#[]]
								ifFalse: [line copyFrom: colonIndex + 1 to: line size].
							(valueBytes notEmpty and: [valueBytes first = 32])
								ifTrue: [
									valueBytes := valueBytes size = 1
										ifTrue: [#[]]
										ifFalse: [valueBytes copyFrom: 2 to: valueBytes size]]].
					"Field names are ASCII keywords. Decode only after splitting
					the colon and optional space so combining marks remain data."
					value := valueBytes isEmpty
						ifTrue: ['']
						ifFalse: [UnicodeString utf8: valueBytes].
					field = 'event' ifTrue: [eventType := value].
					field = 'data' ifTrue: [data := data , value , lf].
					field = 'id' ifTrue: [
						(valueBytes includes: 0) ifFalse: [identifier := value]].
					field = 'retry' ifTrue: [
						(valueBytes notEmpty and: [
							valueBytes allSatisfy: [:byte | byte between: 48 and: 57]])
								ifTrue: [retry := valueBytes asString asNumber]]]]].
	^events asArray
]

{ #category : 'Parsing' }
McpSseParser >> parseAvailableBytes: bytes do: eventBlock [
	"Dispatch complete UTF-8 SSE frames and return the unfinished bytes.
	 Scan line endings before decoding, preserving split UTF-8 and CRLF.
	 Input is raw bytes, including any bytes retained from the last call.

	 Arguments:
		bytes - <ByteArray> incoming chunk appended to unparsed remainder.
		eventBlock - <Block> [:event | ...] callback for each parsed event.
	 Answers:
		<ByteArray> unconsumed trailing bytes."

	| position lineStart frameStart byte nextPosition frameString rawFrame |

	bytes ifNil: [^#[]].
	bytes isEmpty ifTrue: [^#[]].
	position := 1.
	lineStart := 1.
	frameStart := 1.
	[position <= bytes size] whileTrue: [
		byte := bytes at: position.
		(byte = 13 or: [byte = 10])
			ifTrue: [
				(byte = 13 and: [position = bytes size])
					ifTrue: [^bytes copyFrom: frameStart to: bytes size].

				nextPosition := position + 1.
				(byte = 13 and: [nextPosition <= bytes size and: [(bytes at: nextPosition) = 10]])
					ifTrue: [nextPosition := nextPosition + 1].

				position = lineStart
					ifTrue: [
						rawFrame := bytes copyFrom: frameStart to: nextPosition - 1.
						frameString := (UnicodeString utf8: rawFrame repair: true) asString.
						(self parse: frameString) do: eventBlock.
						frameStart := nextPosition].
				lineStart := nextPosition.
				position := nextPosition]
			ifFalse: [position := position + 1]].
	^frameStart > bytes size
		ifTrue: [#[]]
		ifFalse: [bytes copyFrom: frameStart to: bytes size]
]
