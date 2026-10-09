"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# JcsJSONReader

`JcsJSONReader` parses JSON under the stricter input rules required by JCS.

## Responsibilities

- Reject duplicate object members and non-canonical numeric input.
- Translate parser failures to the JCS-specific exception contract.

## Lifecycle and boundaries

A reader is confined to one parse and must not be shared concurrently.
"
Class {
	#name : 'JcsJSONReader',
	#superclass : 'McpJSONReader',
	#category : 'JsonCanonicalizationApp'
}

{ #category : 'Parsing' }
JcsJSONReader class >> fromString: aString [
	"Parse exactly one RFC 8785-compatible JSON value.

	 Arguments:
		aString - <String> JSON source text.
	 Answers:
		<Object> the parsed JSON model value.
	 Raises:
		<JcsInvalidJsonError> for a non-String or invalid document."

	| reader value |

	(aString isString and: [aString isSymbol not])
		ifFalse: [JcsInvalidJsonError signal: 'JSON source must be a string'].
	reader := self on: aString readStream.
	reader propertyNamesAsSymbols: false.
	value := reader next.
	reader consumeWhitespace.
	reader failIfNotAtEnd.
	^value
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
JcsJSONReader >> error: aString [
	"Translate a reader failure into the module-specific exception.

	 Arguments:
		aString - <String> diagnostic text.
	 Raises:
		<JcsInvalidJsonError> always."

	JcsInvalidJsonError signal: aString
]

{ #category : 'Parsing',
  #vaVisibility : 'private' }
JcsJSONReader >> parseMap [
	"Parse an object while rejecting duplicate member names.

	 Answers:
		<KeyedCollection> parsed object members with String keys.
	 Raises:
		<JcsInvalidJsonError> if an object name occurs more than once."

	| map |

	map := self mapClass new.
	self parseMapKeysAndValuesDo: [:key :value |
		(map includesKey: key) ifTrue: [self error: 'Duplicate JSON object name: ' , key].
		map at: key put: value].
	^map
]

{ #category : 'Parsing',
  #vaVisibility : 'private' }
JcsJSONReader >> parseNumber [
	"Parse one token with strict JSON grammar and binary64 limits.

	 Answers:
		<Number> an Integer without a fraction or exponent, otherwise Float.
	 Raises:
		<JcsInvalidJsonError> for malformed or non-representable input."

	| token hasFractionOrExponent number first |

	hasFractionOrExponent := false.
	token :=
		String streamContents: [:stream |
			(readStream peekFor: $-) ifTrue: [stream nextPut: $-].
			readStream atEnd ifTrue: [self error: 'JSON number requires a digit'].
			first := readStream next.
			first isDigit ifFalse: [self error: 'JSON number requires a digit'].
			stream nextPut: first.
			first = $0
				ifTrue: [
					(readStream atEnd not and: [readStream peek isDigit])
						ifTrue: [self error: 'JSON number cannot contain a leading zero']]
				ifFalse: [
					[readStream atEnd not and: [readStream peek isDigit]]
						whileTrue: [stream nextPut: readStream next]].
			(readStream atEnd not and: [readStream peek = $.])
				ifTrue: [
					hasFractionOrExponent := true.
					stream nextPut: readStream next.
					(readStream atEnd or: [readStream peek isDigit not])
						ifTrue: [self error: 'JSON fraction requires a digit'].
					[readStream atEnd not and: [readStream peek isDigit]]
						whileTrue: [stream nextPut: readStream next]].
			(readStream atEnd not and: [readStream peek = $e or: [readStream peek = $E]])
				ifTrue: [
					hasFractionOrExponent := true.
					stream nextPut: readStream next.
					(readStream atEnd not and: [readStream peek = $+ or: [readStream peek = $-]])
						ifTrue: [stream nextPut: readStream next].
					(readStream atEnd or: [readStream peek isDigit not])
						ifTrue: [self error: 'JSON exponent requires a digit'].
					[readStream atEnd not and: [readStream peek isDigit]]
						whileTrue: [stream nextPut: readStream next]]].
	self consumeWhitespace.
	number := hasFractionOrExponent
		ifTrue: [Float readFrom: token]
		ifFalse: [Integer readFrom: token].
	number isFloat
		ifTrue: [
			number isFinite ifFalse: [self error: 'JSON number is outside the binary64 finite range'].
			(number isZero and: [token anySatisfy: [:character | character between: $1 and: $9]])
				ifTrue: [self error: 'JSON number underflows the binary64 finite range']].
	^number
]
