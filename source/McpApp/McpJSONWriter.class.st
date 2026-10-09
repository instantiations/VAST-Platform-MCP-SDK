Class {
	#name : 'McpJSONWriter',
	#superclass : 'NeoJSONWriter',
	#category : 'McpApp'
}

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONWriter >> encodeChar: char [

	(char codePoint isNil or: [ char = Grapheme crlf ]) ifTrue: [
		char unicodeScalars do: [ :unicodeScalar |
			super encodeChar: unicodeScalar asGrapheme ]
	] ifFalse: [
		super encodeChar: char ]
]
