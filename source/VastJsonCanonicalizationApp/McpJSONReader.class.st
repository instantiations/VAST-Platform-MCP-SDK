Class {
	#name : 'McpJSONReader',
	#superclass : 'NeoJSONReader',
	#category : 'VastJsonCanonicalizationApp'
}

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONReader >> characterClass [

	^ Grapheme
]

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONReader >> characterOrGraphemeFor: grapheme [

	^ grapheme codePoint <= 127
		ifTrue: [ Character codePoint: grapheme codePoint ]
		ifFalse: [ grapheme ]
]

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONReader >> parseCharacterHex [

	^ self characterOrGraphemeFor: super parseCharacterHex
]

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONReader >> stringStreamContents: block [

	(stringStream isKindOf: UnicodeWriteStream) ifTrue: [
		stringStream := nil ].
	^ super stringStreamContents: block
]

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONReader >> unescapeChar: char [

	^ self characterOrGraphemeFor: (super unescapeChar: char)
]
