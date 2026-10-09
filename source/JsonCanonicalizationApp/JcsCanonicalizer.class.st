"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# JcsCanonicalizer

`JcsCanonicalizer` implements deterministic JSON Canonicalization Scheme
output.

## Responsibilities

- Serialize supported JSON values with stable key and number ordering.
- Compare object keys by UTF-16 code units as required by JCS.

## Lifecycle and boundaries

Instances hold no shared state and are safe for independent calls.
"
Class {
	#name : 'JcsCanonicalizer',
	#superclass : 'Object',
	#category : 'JsonCanonicalizationApp'
}

{ #category : 'Formatting' }
JcsCanonicalizer class >> canonicalStringFor: anObject [
	"Answer the RFC 8785 canonical JSON representation of anObject.

	 Arguments:
		anObject - <Object> a supported I-JSON model value.
	 Answers:
		<String> canonical JSON text to be encoded as UTF-8 when needed.
	 Raises:
		<JcsInvalidJsonError> if a value cannot be represented safely."

	^String streamContents: [:stream | self new writeValue: anObject on: stream]
]

{ #category : 'Formatting' }
JcsCanonicalizer class >> canonicalStringFromJson: aString [
	"Parse and canonicalize one complete JSON document.

	 Arguments:
		aString - <String> JSON source text.
	 Answers:
		<String> canonical JSON text.
	 Raises:
		<JcsInvalidJsonError> if the source or parsed value is invalid."

	^self canonicalStringFor: (JcsJSONReader fromString: aString)
]

{ #category : 'Parsing' }
JcsCanonicalizer class >> parseJson: aString [
	"Parse one complete document with the strict JCS reader.

	 Arguments:
		aString - <String> JSON source text.
	 Answers:
		<Object> the parsed JSON model value.
	 Raises:
		<JcsInvalidJsonError> if the source is invalid."

	^JcsJSONReader fromString: aString
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> appendUtf16For: codePoint to: aCollection [
	"Append one Unicode scalar value as unsigned UTF-16 code units.

	 Arguments:
		codePoint - <Integer> a Unicode scalar value.
		aCollection - <Collection> destination for integer code units.
	 Answers:
		<Collection> aCollection.
	 Raises:
		<JcsInvalidJsonError> if codePoint is not a Unicode scalar."

	(codePoint between: 16rD800 and: 16rDFFF)
		ifTrue: [JcsInvalidJsonError signal: 'JCS strings cannot contain surrogates'].
	(codePoint between: 0 and: 16r10FFFF)
		ifFalse: [JcsInvalidJsonError signal: 'JCS string code point is out of range'].
	codePoint <= 16rFFFF
		ifTrue: [
			aCollection add: codePoint.
			^aCollection].
	aCollection
		add: 16rD800 + ((codePoint - 16r10000) // 16r400);
		add: 16rDC00 + ((codePoint - 16r10000) \\ 16r400).
	^aCollection
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> compareNumerator: numerator denominator: denominator toPowerOfTen: exponent [
	"Compare one exact positive fraction with ten raised to exponent.

	 Arguments:
		numerator - <Integer> positive fraction numerator.
		denominator - <Integer> positive fraction denominator.
		exponent - <Integer> decimal exponent.
	 Answers:
		<Integer> -1, 0, or 1 for less than, equal to, or greater than."

	| left right |

	exponent >= 0
		ifTrue: [
			left := numerator.
			right := denominator * (10 raisedToInteger: exponent)]
		ifFalse: [
			left := numerator * (10 raisedToInteger: exponent negated).
			right := denominator].
	left < right ifTrue: [^-1].
	left > right ifTrue: [^1].
	^0
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> decimalExponentForNumerator: numerator denominator: denominator approximately: aFloat [
	"Answer the exact floor of the fraction's base-ten logarithm.

	 Arguments:
		numerator - <Integer> positive fraction numerator.
		denominator - <Integer> positive fraction denominator.
		aFloat - <Float> approximate value used as the initial estimate.
	 Answers:
		<Integer> the corrected decimal exponent."

	| exponent |

	exponent := aFloat scale.
	[(self compareNumerator: numerator denominator: denominator toPowerOfTen: exponent + 1) >= 0]
		whileTrue: [exponent := exponent + 1].
	[(self compareNumerator: numerator denominator: denominator toPowerOfTen: exponent) < 0]
		whileTrue: [exponent := exponent - 1].
	^exponent
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> decimalValueForSignificand: significand scale: scale [
	"Answer the exact rational value represented by a decimal pair.

	 Arguments:
		significand - <Integer> decimal significand.
		scale - <Integer> power of ten applied to significand.
	 Answers:
		<Number> an exact Integer or Fraction."

	^scale >= 0
		ifTrue: [significand * (10 raisedToInteger: scale)]
		ifFalse: [Fraction numerator: significand denominator: (10 raisedToInteger: scale negated)]
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> ecmaStringForSignificand: significand scale: scale [
	"Format one normalized positive decimal with ECMAScript thresholds.

	 Arguments:
		significand - <Integer> positive normalized significand.
		scale - <Integer> power of ten applied to significand.
	 Answers:
		<String> fixed or scientific decimal text."

	| digits size position exponent mantissa |

	digits := significand printString.
	size := digits size.
	position := size + scale.
	(position > 0 and: [position <= 21])
		ifTrue: [
			position >= size ifTrue: [^digits , (self zeros: position - size)].
			^(digits copyFrom: 1 to: position) , '.' , (digits copyFrom: position + 1 to: size)].
	(position <= 0 and: [position > -6]) ifTrue: [^'0.' , (self zeros: position negated) , digits].
	mantissa :=
		size = 1
			ifTrue: [digits]
			ifFalse: [(digits copyFrom: 1 to: 1) , '.' , (digits copyFrom: 2 to: size)].
	exponent := position - 1.
	^mantissa , 'e' , (exponent >= 0 ifTrue: ['+'] ifFalse: ['']) , exponent printString
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> exactFractionFor: aFloat [
	"Decompose a positive finite binary64 value into an exact fraction.

	 Arguments:
		aFloat - <Float> positive finite value.
	 Answers:
		<Association> integer numerator mapped to a positive denominator."

	| bits exponentBits fractionBits significand binaryExponent numerator |

	bits := 0.
	System bigEndian
		ifTrue: [1 to: 8 do: [:index | bits := (bits bitShift: 8) + (aFloat at: index)]]
		ifFalse: [8 to: 1 by: -1 do: [:index | bits := (bits bitShift: 8) + (aFloat at: index)]].
	exponentBits := (bits bitShift: -52) bitAnd: 16r7FF.
	fractionBits := bits bitAnd: 16rFFFFFFFFFFFFF.
	exponentBits = 0
		ifTrue: [
			significand := fractionBits.
			binaryExponent := -1074]
		ifFalse: [
			significand := (1 bitShift: 52) + fractionBits.
			binaryExponent := exponentBits - 1023 - 52].
	binaryExponent >= 0 ifTrue: [^(significand bitShift: binaryExponent) -> 1].
	numerator := significand.
	^numerator -> (1 bitShift: binaryExponent negated)
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> normalizedSignificand: significand scale: scale [
	"Remove insignificant trailing zeros from a decimal pair.

	 Arguments:
		significand - <Integer> positive decimal significand.
		scale - <Integer> power of ten applied to significand.
	 Answers:
		<Association> normalized significand mapped to adjusted scale."

	| normalized adjustedScale |

	normalized := significand.
	adjustedScale := scale.
	[normalized > 0 and: [normalized \\ 10 = 0]] whileTrue: [
		normalized := normalized // 10.
		adjustedScale := adjustedScale + 1].
	^normalized -> adjustedScale
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> record: candidate isBetterThan: current [
	"Answer whether candidate is the preferred decimal record.

	 Arguments:
		candidate - <Array> text, distance, precision, and parity.
		current - <Array> current best record, or nil.
	 Answers:
		<Boolean> true when candidate should replace current."

	current ifNil: [^true].
	(candidate at: 3) < (current at: 3) ifTrue: [^true].
	(candidate at: 3) > (current at: 3) ifTrue: [^false].
	(candidate at: 2) < (current at: 2) ifTrue: [^true].
	(candidate at: 2) > (current at: 2) ifTrue: [^false].
	^(candidate at: 4) and: [(current at: 4) not]
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> roundedSignificandForNumerator: numerator denominator: denominator scale: scale [
	"Round an exact positive fraction at scale using ties-to-even.

	 Arguments:
		numerator - <Integer> positive fraction numerator.
		denominator - <Integer> positive fraction denominator.
		scale - <Integer> decimal power applied to the result.
	 Answers:
		<Integer> the rounded significand."

	| scaledNumerator scaledDenominator quotient remainder comparison |

	scale >= 0
		ifTrue: [
			scaledNumerator := numerator.
			scaledDenominator := denominator * (10 raisedToInteger: scale)]
		ifFalse: [
			scaledNumerator := numerator * (10 raisedToInteger: scale negated).
			scaledDenominator := denominator].
	quotient := scaledNumerator // scaledDenominator.
	remainder := scaledNumerator \\ scaledDenominator.
	comparison := remainder * 2 - scaledDenominator.
	(comparison > 0 or: [comparison = 0 and: [quotient even not]]) ifTrue: [quotient := quotient + 1].
	^quotient
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> shortestDecimalFor: aFloat [
	"Answer the shortest ECMAScript decimal that round-trips to aFloat.

	 Arguments:
		aFloat - <Float> a finite binary64 value.
	 Answers:
		<String> canonical number text.
	 Raises:
		<JcsInvalidJsonError> if the value is nonfinite or cannot serialize."

	| absolute fraction numerator denominator exponent best seen scale center candidates normalized
	  text value distance record |

	aFloat isFinite ifFalse: [JcsInvalidJsonError signal: 'JCS numbers must be finite'].
	aFloat isZero ifTrue: [^'0'].
	absolute := aFloat abs.
	fraction := self exactFractionFor: absolute.
	numerator := fraction key.
	denominator := fraction value.
	exponent :=
		self decimalExponentForNumerator: numerator denominator: denominator approximately: absolute.
	best := nil.
	seen := Set new.
	1 to: 17 do: [:precision |
		scale := exponent - precision + 1.
		center := self
			roundedSignificandForNumerator: numerator
			denominator: denominator
			scale: scale.
		candidates := Array with: center with: center - 1 with: center + 1.
		candidates do: [:candidate |
			candidate > 0
				ifTrue: [
					normalized := self normalizedSignificand: candidate scale: scale.
					text := self ecmaStringForSignificand: normalized key scale: normalized value.
					(seen includes: text)
						ifFalse: [
							seen add: text.
							(Float readFrom: text) = absolute
								ifTrue: [
									value :=
										self
											decimalValueForSignificand: normalized key
											scale: normalized value.
									distance := (value - (numerator / denominator)) abs.
									record :=
										Array
											with: text
											with: distance
											with: normalized key printString size
											with: normalized key even.
									(self record: record isBetterThan: best) ifTrue: [best := record]]]]]].
	best ifNil: [JcsInvalidJsonError signal: 'Unable to produce a round-trip binary64 decimal'].
	^aFloat sign = -1 ifTrue: ['-' , (best at: 1)] ifFalse: [best at: 1]
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> sortedAssociationsOf: aDictionary [
	"Answer object associations sorted by unsigned UTF-16 key units.

	 Arguments:
		aDictionary - <KeyedCollection> object members.
	 Answers:
		<SortedCollection> associations in canonical order.
	 Raises:
		<JcsInvalidJsonError> if a member name is not a String."

	| associations |

	associations := OrderedCollection new: aDictionary size.
	aDictionary associationsDo: [:association |
		(association key isString and: [association key isSymbol not])
			ifFalse: [JcsInvalidJsonError signal: 'JCS object member names must be strings'].
		associations add: association].
	^associations asSortedCollection: [:left :right | self utf16String: left key lessThan: right key]
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> utf16CodeUnitsFor: aString [
	"Answer the unsigned UTF-16 code units representing aString.

	 Arguments:
		aString - <String> Unicode text.
	 Answers:
		<Array> integer UTF-16 code units.
	 Raises:
		<JcsInvalidJsonError> if the string contains an invalid scalar."

	| units codePoint |

	units := OrderedCollection new: aString size.
	aString do: [:character |
		codePoint := character codePoint.
		codePoint
			ifNil: [
				character unicodeScalars
					do: [:scalar | self appendUtf16For: scalar asGrapheme codePoint to: units]]
			ifNotNil: [self appendUtf16For: codePoint to: units]].
	^units asArray
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> utf16String: leftString lessThan: rightString [
	"Compare two strings as unsigned UTF-16 code-unit sequences.

	 Arguments:
		leftString - <String> left operand.
		rightString - <String> right operand.
	 Answers:
		<Boolean> true when leftString precedes rightString."

	| left right limit |

	left := self utf16CodeUnitsFor: leftString.
	right := self utf16CodeUnitsFor: rightString.
	limit := left size min: right size.
	1 to: limit do: [:index |
		(left at: index) < (right at: index) ifTrue: [^true].
		(left at: index) > (right at: index) ifTrue: [^false]].
	^left size < right size
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeArray: aCollection on: aStream [
	"Write one canonical JSON array while preserving element order.

	 Arguments:
		aCollection - <SequenceableCollection> supported JSON values.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver."

	aStream nextPut: $[.
	aCollection doWithIndex: [:value :index |
		index > 1 ifTrue: [aStream nextPut: $,].
		self writeValue: value on: aStream].
	aStream nextPut: $].
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeControlCode: codePoint on: aStream [
	"Write one ASCII control code as a lowercase Unicode escape.

	 Arguments:
		codePoint - <Integer> a value from 0 through 31.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver."

	| digits |

	digits := '0123456789abcdef'.
	aStream nextPutAll: '\u'.
	12
		to: 0
		by: -4
		do: [:shift |
			aStream nextPut: (digits at: ((codePoint bitShift: shift negated) bitAnd: 15) + 1)].
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeFloat: aFloat on: aStream [
	"Write one canonical finite IEEE-754 binary64 number.

	 Arguments:
		aFloat - <Float> value to serialize.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver."

	aStream nextPutAll: (self shortestDecimalFor: aFloat).
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeInteger: anInteger on: aStream [
	"Write one exactly representable binary64 integer in canonical form.

	 Integers in the ECMAScript safe range can be written directly. Larger
	 integers are converted only when their binary64 value reconstructs the
	 original Integer exactly.

	 Arguments:
		anInteger - <Integer> value to serialize.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver.
	 Raises:
		<JcsInvalidJsonError> if binary64 cannot preserve anInteger."

	| binary64 |

	anInteger abs <= 9007199254740991
		ifTrue: [
			anInteger printOn: aStream.
			^self].
	[binary64 := anInteger asFloat]
		on: Error
		do: [:error | JcsInvalidJsonError signal: 'JCS integer is outside the binary64 finite range'].
	(binary64 isFinite and: [binary64 truncated = anInteger])
		ifFalse: [JcsInvalidJsonError signal: 'JCS integer is not exactly representable as binary64'].
	aStream nextPutAll: (self shortestDecimalFor: binary64).
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeObject: aDictionary on: aStream [
	"Write one canonical JSON object with recursively serialized values.

	 Arguments:
		aDictionary - <KeyedCollection> object members.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver."

	aStream nextPut: ${.
	(self sortedAssociationsOf: aDictionary) doWithIndex: [:association :index |
		index > 1 ifTrue: [aStream nextPut: $,].
		self writeString: association key on: aStream.
		aStream nextPut: $:.
		self writeValue: association value on: aStream].
	aStream nextPut: $}.
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeString: aString on: aStream [
	"Write one minimally escaped canonical JSON string.

	 Arguments:
		aString - <String> Unicode text.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver.
	 Raises:
		<JcsInvalidJsonError> if aString contains invalid Unicode."

	| codePoint |

	aStream nextPut: $".
	aString do: [:character |
		codePoint := character codePoint.
		codePoint
			ifNil: [
				character unicodeScalars
					do: [:scalar | self writeUnicodeScalar: scalar asGrapheme on: aStream]]
			ifNotNil: [self writeUnicodeScalar: character on: aStream]].
	aStream nextPut: $".
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeUnicodeScalar: aCharacter on: aStream [
	"Write one Unicode scalar with the RFC 8785 escaping rules.

	 Arguments:
		aCharacter - <Character> Unicode scalar.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver.
	 Raises:
		<JcsInvalidJsonError> if the character is not a Unicode scalar."

	| codePoint |

	codePoint := aCharacter codePoint.
	(codePoint between: 16rD800 and: 16rDFFF)
		ifTrue: [JcsInvalidJsonError signal: 'JCS strings cannot contain surrogates'].
	(codePoint between: 0 and: 16r10FFFF)
		ifFalse: [JcsInvalidJsonError signal: 'JCS string code point is out of range'].
	codePoint = 8
		ifTrue: [
			aStream nextPutAll: '\b'.
			^self].
	codePoint = 9
		ifTrue: [
			aStream nextPutAll: '\t'.
			^self].
	codePoint = 10
		ifTrue: [
			aStream nextPutAll: '\n'.
			^self].
	codePoint = 12
		ifTrue: [
			aStream nextPutAll: '\f'.
			^self].
	codePoint = 13
		ifTrue: [
			aStream nextPutAll: '\r'.
			^self].
	codePoint = 34
		ifTrue: [
			aStream nextPutAll: '\"'.
			^self].
	codePoint = 92
		ifTrue: [
			aStream nextPutAll: '\\'.
			^self].
	codePoint < 32
		ifTrue: [
			self writeControlCode: codePoint on: aStream.
			^self].
	aStream nextPut: aCharacter.
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> writeValue: aValue on: aStream [
	"Write one recursively validated value from the supported JSON model.

	 Arguments:
		aValue - <Object> supported JSON model value.
		aStream - <Stream> destination character stream.
	 Answers:
		<JcsCanonicalizer> the receiver.
	 Raises:
		<JcsInvalidJsonError> if aValue is unsupported."

	aValue isNil
		ifTrue: [
			aStream nextPutAll: 'null'.
			^self].
	aValue == true
		ifTrue: [
			aStream nextPutAll: 'true'.
			^self].
	aValue == false
		ifTrue: [
			aStream nextPutAll: 'false'.
			^self].
	(aValue isString and: [aValue isSymbol not])
		ifTrue: [
			self writeString: aValue on: aStream.
			^self].
	aValue isInteger
		ifTrue: [
			self writeInteger: aValue on: aStream.
			^self].
	aValue isFloat
		ifTrue: [
			self writeFloat: aValue on: aStream.
			^self].
	aValue isDictionary
		ifTrue: [
			self writeObject: aValue on: aStream.
			^self].
	(aValue isKindOf: SequenceableCollection)
		ifTrue: [
			self writeArray: aValue on: aStream.
			^self].
	JcsInvalidJsonError signal: 'Unsupported JCS value class: ' , aValue class name
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
JcsCanonicalizer >> zeros: count [
	"Answer a string containing count ASCII zero characters.

	 Arguments:
		count - <Integer> requested count.
	 Answers:
		<String> an empty string when count is not positive."

	| result |

	count <= 0 ifTrue: [^''].
	result := String new: count.
	result atAllPut: $0.
	^result
]
