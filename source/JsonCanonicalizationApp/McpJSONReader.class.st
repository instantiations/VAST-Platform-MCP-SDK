Class {
	#name : 'McpJSONReader',
	#superclass : 'NeoJSONReader',
	#category : 'JsonCanonicalizationApp'
}

{ #category : 'convenience' }
McpJSONReader class >> fromString: string [

	^ (super on: (McpPeekableStream on: (McpCharacterGraphemeStream on: string unicodeScalars))) next
]

{ #category : 'convenience' }
McpJSONReader class >> fromString: string as: schema [

	^ (super on: (McpPeekableStream on: (McpCharacterGraphemeStream on: string unicodeScalars))) nextAs: schema
]

{ #category : 'instance creation' }
McpJSONReader class >> on: readStream [

	^ super on: (McpPeekableStream on: (McpCharacterGraphemeStream on: (McpUnicodeScalarStream on: readStream)))
]

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
