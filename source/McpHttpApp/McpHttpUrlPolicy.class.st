"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Parses HTTP origin identities and resolves relative redirect locations.
Class-side operations retain no mutable state. Resource comparison and MCP
redirect validation share this implementation; no network I/O is performed.
"
Class {
	#name : 'McpHttpUrlPolicy',
	#superclass : 'Object',
	#category : 'McpHttpApp'
}

{ #category : 'Validation' }
McpHttpUrlPolicy class >> allows: destination from: source [
	"Allow one origin or the default-port HTTP-to-HTTPS upgrade.
	Arguments:
		destination - <SstHttpUrl> proposed destination.
		source - <SstHttpUrl> URL of the request just sent.
	Answers:
		<Boolean>. Changed or added userinfo is refused."
	| origin target oldUser newUser |
	origin := self originOf: source.
	target := self originOf: destination.
	oldUser := source userinfo ifNil: [''].
	newUser := destination userinfo ifNil: [''].
	(newUser isEmpty not and: [newUser ~= oldUser]) ifTrue: [^false].
	origin = target ifTrue: [^true].
	^origin second = target second and: [
		origin first = 'http' and: [origin third = 80 and: [
			target first = 'https' and: [target third = 443]]]]

]

{ #category : 'Validation' }
McpHttpUrlPolicy class >> normalizePath: pathText [
	"Remove literal dot segments without decoding escaped path separators.
	Arguments:
		pathText - <String> absolute HTTP path.
	Answers:
		<String> normalized path."
	| segments start token result |
	pathText isEmpty ifTrue: [^'/'].
	segments := OrderedCollection new.
	start := 2.
	2 to: pathText size + 1 do: [:index |
		(index > pathText size or: [(pathText at: index) = $/]) ifTrue: [
			token := pathText copyFrom: start to: index - 1.
			token = '..' ifTrue: [
				segments isEmpty ifFalse: [segments removeLast]].
			(#('.' '..') includes: token)
				ifFalse: [segments add: token]
				ifTrue: [index > pathText size ifTrue: [segments add: '']].
			start := index + 1]].
	result := String streamContents: [:out |
		segments do: [:segment | out nextPut: $/; nextPutAll: segment]].
	^result isEmpty ifTrue: ['/'] ifFalse: [result]

]

{ #category : 'Validation' }
McpHttpUrlPolicy class >> originOf: endpoint [
	"Answer normalized scheme, host and effective port, including IPv6.
	Arguments:
		endpoint - <SstHttpUrl> absolute HTTP URL.
	Answers:
		<Array> scheme, lowercase host, and integer port."
	| schemeText addressText hostText portText separator portNumber |
	(endpoint isKindOf: SstHttpUrl)
		ifFalse: [self error: 'Expected an HTTP URL'].
	schemeText := endpoint scheme asLowercase.
	(#('http' 'https') includes: schemeText)
		ifFalse: [self error: 'Expected an HTTP or HTTPS scheme'].
	addressText := endpoint address.
	(addressText isString and: [addressText isEmpty not])
		ifFalse: [self error: 'HTTP host is required'].
	(addressText anySatisfy: [:c |
		c codePoint <= 32 or: [c = $\ or: [c = $@]]])
		ifTrue: [self error: 'Invalid HTTP authority'].
	portText := nil.
	addressText first = $[ ifTrue: [
		separator := addressText indexOf: $].
		separator = 0 ifTrue: [self error: 'Invalid IPv6 authority'].
		hostText := addressText copyFrom: 1 to: separator.
		separator < addressText size ifTrue: [
			(addressText at: separator + 1) = $:
				ifFalse: [self error: 'Invalid HTTP port separator'].
			portText := addressText copyFrom: separator + 2
				to: addressText size]
	] ifFalse: [
		separator := addressText indexOf: $:.
		hostText := separator = 0 ifTrue: [addressText]
			ifFalse: [addressText copyFrom: 1 to: separator - 1].
		separator > 0 ifTrue: [
			portText := addressText copyFrom: separator + 1
				to: addressText size]].
	hostText isEmpty ifTrue: [self error: 'HTTP host is required'].
	portNumber := schemeText = 'https' ifTrue: [443] ifFalse: [80].
	portText ifNotNil: [
		(portText isEmpty or: [
			(portText allSatisfy: [:c | c between: $0 and: $9]) not])
			ifTrue: [self error: 'Invalid HTTP port'].
		portNumber := portText asNumber.
		(portNumber between: 1 and: 65535)
			ifFalse: [self error: 'HTTP port is outside its range']].
	^Array with: schemeText with: hostText asLowercase with: portNumber

]

{ #category : 'Validation' }
McpHttpUrlPolicy class >> resolve: locationText against: source [
	"Resolve an HTTP Location, preserving query and inherited userinfo.
	Arguments:
		locationText - <String> URI reference.
		source - <SstHttpUrl> current request URL.
	Answers:
		<SstHttpUrl> absolute destination with no fragment."
	| location hashIndex candidate baseText pathText slashIndex colonIndex |
	(locationText isString and: [locationText isSymbol not])
		ifFalse: [self error: 'HTTP redirect Location must be text'].
	(locationText anySatisfy: [:c | c codePoint <= 32 or: [c = $\]])
		ifTrue: [self error: 'Invalid HTTP redirect Location'].
	location := locationText.
	hashIndex := location indexOf: $#.
	hashIndex > 0 ifTrue: [
		location := location copyFrom: 1 to: hashIndex - 1].
	baseText := source scheme , '://'.
	source userinfo ifNotNil: [:info |
		info isEmpty not ifTrue: [baseText := baseText , info , '@']].
	baseText := baseText , source address.
	colonIndex := location indexOf: $:.
	slashIndex := location indexOf: $/.
	(colonIndex > 0 and: [
		(location indexOf: $?) = 0 or: [colonIndex < (location indexOf: $?)]]
		) ifTrue: [
			(slashIndex > 0 and: [slashIndex < colonIndex])
				ifTrue: [colonIndex := 0]].
	((colonIndex > 0 and: [slashIndex = 0 or: [colonIndex < slashIndex]])
		and: [(location indexOf: $?) = 0 or: [colonIndex < (location indexOf:
			$?)]] )
		ifTrue: [candidate := location sstAsUrl]
		ifFalse: [
			(location beginsWithSubCollection: '//')
				ifTrue: [candidate := (source scheme , ':' , location) sstAsUrl]
				ifFalse: [
					location isEmpty ifTrue: [^source copy].
					location first = $/ ifTrue: [
						candidate := (baseText , location) sstAsUrl]
					ifFalse: [
						pathText := source path.
						pathText isEmpty ifTrue: [pathText := '/'].
						location first = $? ifTrue: [
							candidate := (baseText , pathText , location)
				sstAsUrl]
						ifFalse: [
							slashIndex := pathText lastIndexOf: $/.
							pathText := pathText copyFrom: 1 to: slashIndex.
							candidate := (baseText , pathText , location)
				sstAsUrl]]]].
	self originOf: candidate.
	candidate path: (self normalizePath: candidate path).
	^candidate

]

{ #category : 'Validation' }
McpHttpUrlPolicy class >> resourceKey: resourceText [
	"Normalize a verified token resource as a URL, trailing slash aside.
	Arguments:
		resourceText - <String> HTTP resource identifier.
	Answers:
		<Array> origin and case-sensitive path/query, or nil if invalid."
	| endpoint origin suffix queryText |
	(resourceText isString and: [resourceText isSymbol not]) ifFalse: [^nil].
	[
		endpoint := resourceText sstAsUrl.
		origin := self originOf: endpoint.
		suffix := endpoint path.
		suffix isEmpty ifTrue: [suffix := '/'].
		queryText := endpoint query.
		queryText isEmpty ifFalse: [suffix := suffix , '?' , queryText].
		suffix last = $/ ifTrue: [
			suffix := suffix copyFrom: 1 to: suffix size - 1].
		^Array with: origin with: suffix
			with: (endpoint userinfo ifNil: [''])
	] on: Error do: [:failure | ^nil]

]
