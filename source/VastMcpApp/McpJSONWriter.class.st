Class {
	#name : 'McpJSONWriter',
	#superclass : 'NeoJSONWriter',
	#category : 'VastMcpApp'
}

{ #category : 'private',
  #vaVisibility : 'private' }
McpJSONWriter >> encodeChar: char [

	char = Grapheme crlf ifTrue: [
		self encodeChar: Character cr; encodeChar: Character lf
	] ifFalse: [
		super encodeChar: char ]
]
