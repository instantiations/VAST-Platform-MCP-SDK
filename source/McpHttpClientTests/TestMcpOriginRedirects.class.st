"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Deterministic, self-contained MCP 2.2.0 regression tests.
Fixtures own their state and do not contact external services.
"
Class {
	#name : 'TestMcpOriginRedirects',
	#superclass : 'TestCase',
	#category : 'McpHttpClientTests'
}

{ #category : 'Fixtures',
  #vaVisibility : 'private' }
TestMcpOriginRedirects >> requestMethod: verb [
	"Build a real SST message whose body and authorization must survive.
	Arguments:
		verb - <String> HTTP method.
	Answers:
		<SstCommunicationMessage> request."
	^SstCommunicationMessage new
		header: (SstHttpRequestHeader new command: verb; version: 'HTTP/1.1';
			url: '/mcp'; host: 'example.com';
			at: 'Authorization' put: 'Bearer private-token'; yourself);
		contents: '{"method":"tools/call"}' asUtf8Bytes; yourself

]

{ #category : 'Fixtures',
  #vaVisibility : 'private' }
TestMcpOriginRedirects >> responseStatus: code location: target [
	"Answer a finite scripted response.
	Arguments:
		code - <Integer> HTTP response code.
		target - <String | nil> Location header.
	Answers:
		<McpHttpClientTestResponse> response."
	| responseHeader |
	responseHeader := McpHttpClientTestResponseHeader new statusCode: code;
		contentType: 'application/json'; yourself.
	target ifNotNil: [responseHeader at: 'Location' put: target].
	^McpHttpClientTestResponse new header: responseHeader;
		contents: '{}' asUtf8Bytes; yourself

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testAllowedOriginsAndDefaultPortUpgrade [
	"Only equivalent origins or the default-port TLS upgrade are allowed."
	| source |
	source := 'http://example.com/mcp' sstAsUrl.
	#('http://EXAMPLE.COM:80/next' 'https://example.com/next'
		'https://example.com:443/next') do: [:target |
			self assert: (McpHttpUrlPolicy
				allows: target sstAsUrl from: source)].
	#('http://other.example/mcp' 'http://example.com:81/mcp'
		'https://example.com:444/mcp') do: [:target |
			self deny: (McpHttpUrlPolicy
				allows: target sstAsUrl from: source)].
	self deny: (McpHttpUrlPolicy allows: source
		from: 'https://example.com/mcp' sstAsUrl)

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testCrossOriginRedirectNeverSendsSecondRequest [
	"A refused redirect never sends credentials or body to the other origin."
	| script observations probe |
	script := OrderedCollection with:
		(self responseStatus: 307 location: 'https://other.example/mcp').
	observations := OrderedCollection new.
	probe := TestMcpOriginHttpClientProbe responses: script
		observations: observations.
	[
		self should: [probe send: (self requestMethod: 'POST')
			to: 'https://example.com/mcp' sstAsUrl
			redirect: 20 assemblerPolicy: nil] raise: Error
	] ensure: [probe shutDown].
	self assert: observations size equals: 1.
	self assert: probe closedHopCount equals: 1

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testGet302AndRedirectBudget [
	"GET preserves its method, and redirect loops stop at the budget."
	| script observations probe |
	script := OrderedCollection new.
	3 timesRepeat: [script add: (self responseStatus: 302 location: '/again')].
	observations := OrderedCollection new.
	probe := TestMcpOriginHttpClientProbe responses: script
		observations: observations.
	[
		self should: [probe send: (self requestMethod: 'GET')
			to: 'https://example.com/mcp' sstAsUrl
			redirect: 2 assemblerPolicy: nil] raise: Error
	] ensure: [probe shutDown].
	self assert: observations size equals: 3.
	self assert: probe closedHopCount equals: 3.
	observations do: [:each |
		self assert: each value header command equals: 'GET']

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testIpv6OriginAndNondefaultPortUpgrade [
	"Bracketed IPv6 and explicit ports participate in origin comparisons."
	self assert: (McpHttpUrlPolicy
		allows: 'https://[::1]:443/b' sstAsUrl
		from: 'https://[::1]/a' sstAsUrl).
	self deny: (McpHttpUrlPolicy
		allows: 'https://example.com:8080/b' sstAsUrl
		from: 'http://example.com:8080/a' sstAsUrl)

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testPost302IsRefusedWithoutDroppingBody [
	"POST redirects that Python would rewrite to GET are refused."
	| script observations probe |
	script := OrderedCollection with: (self responseStatus: 302 location:
		'/new').
	observations := OrderedCollection new.
	probe := TestMcpOriginHttpClientProbe responses: script
		observations: observations.
	[
		self should: [probe send: (self requestMethod: 'POST')
			to: 'https://example.com/mcp' sstAsUrl
			redirect: 20 assemblerPolicy: nil] raise: Error
	] ensure: [probe shutDown].
	self assert: observations size equals: 1.
	self assert: observations first value header command equals: 'POST'

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testPost307PreservesMethodBodyAndAuthorization [
	"The real send loop follows a same-origin 307 and owns both hops."
	| script observations probe request result redirected |
	script := OrderedCollection new
		add: (self responseStatus: 307 location: '/mcp/');
		add: (self responseStatus: 200 location: nil); yourself.
	observations := OrderedCollection new.
	probe := TestMcpOriginHttpClientProbe responses: script
		observations: observations.
	request := self requestMethod: 'POST'.
	[result := probe send: request to: 'https://example.com/mcp' sstAsUrl
		redirect: 20 assemblerPolicy: nil] ensure: [probe shutDown].
	self assert: result header statusCode equals: 200.
	self assert: observations size equals: 2.
	redirected := observations second value.
	self assert: observations second key path equals: '/mcp/'.
	self assert: redirected header command equals: 'POST'.
	self assert: redirected contents equals: request contents.
	self assert: (redirected header at: 'Authorization')
		equals: 'Bearer private-token'.
	self assert: probe closedHopCount equals: 2

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testRelativeAndQueryRedirectsResolve [
	"Resolve relative, absolute-path, query-only and network-path references."
	| source target |
	source := 'https://example.com/a/mcp?old=1' sstAsUrl.
	target := McpHttpUrlPolicy resolve: '../next?x=1' against: source.
	self assert: target path equals: '/next'.
	self assert: target query equals: 'x=1'.
	target := McpHttpUrlPolicy resolve: '?next=https://other.example'
		against: source.
	self assert: target path equals: '/a/mcp'.
	self assert: target query equals: 'next=https://other.example'.
	target := McpHttpUrlPolicy resolve: '//other.example/path' against: source.
	self deny: (McpHttpUrlPolicy allows: target from: source)

]

{ #category : 'Testing' }
TestMcpOriginRedirects >> testUserinfoCannotBeIntroducedOrChanged [
	"A relative redirect may retain configured credentials but cannot add them."
	| source destination |
	source := 'https://old:secret@example.com/a/mcp' sstAsUrl.
	destination := McpHttpUrlPolicy resolve: '../next' against: source.
	self assert: (McpHttpUrlPolicy allows: destination from: source).
	self deny: (McpHttpUrlPolicy
		allows: 'https://new:secret@example.com/next' sstAsUrl from: source).
	self deny: (McpHttpUrlPolicy
		allows: source from: 'https://example.com/mcp' sstAsUrl)

]
