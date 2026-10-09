Class {
	#name : 'TestMcpUriTemplateRfc6570',
	#superclass : 'TestCase',
	#category : 'McpResourceTests'
}

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testIsTemplate [
	"Verify template detection matching RFC 6570 patterns."

	self assert: (McpUriTemplate isTemplate: 'file://docs/{name}').
	self assert: (McpUriTemplate isTemplate: '{a}').
	self assert: (McpUriTemplate isTemplate: 'prefix{+path}/suffix').

	self deny: (McpUriTemplate isTemplate: 'file://docs/readme.txt').
	self deny: (McpUriTemplate isTemplate: '').
	self deny: (McpUriTemplate isTemplate: '{').
	self deny: (McpUriTemplate isTemplate: '}').
	self deny: (McpUriTemplate isTemplate: '}{')
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testLevel1SimpleVariable [
	"Verify Level 1 simple variable matching and expansion."

	| tmpl matched expanded |

	tmpl := McpUriTemplate template: 'file://docs/{name}'.
	matched := tmpl matchUri: 'file://docs/guide.md'.
	self assert: matched notNil.
	self assert: (matched at: 'name') equals: 'guide.md'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'name' -> 'guide.md').
	self assert: expanded equals: 'file://docs/guide.md'.

	"Single segment must not match slashes"
	self assert: (tmpl matchUri: 'file://docs/sub/guide.md') isNil
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testLevel2ReservedAndFragment [
	"Verify Level 2 reserved path and fragment expansion and matching."

	| tmpl matched expanded |

	tmpl := McpUriTemplate template: 'file://docs/{+path}'.
	matched := tmpl matchUri: 'file://docs/sub/deep/readme.txt'.
	self assert: matched notNil.
	self assert: (matched at: 'path') equals: 'sub/deep/readme.txt'.

	tmpl := McpUriTemplate template: 'http://example.com/page{#section}'.
	matched := tmpl matchUri: 'http://example.com/page#intro'.
	self assert: matched notNil.
	self assert: (matched at: 'section') equals: 'intro'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'section' -> 'intro').
	self assert: expanded equals: 'http://example.com/page#intro'
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testLevel3PathAndLabel [
	"Verify Level 3 path segment and dot label matching."

	| tmpl matched expanded |

	tmpl := McpUriTemplate template: 'http://example.com{/dir}/file'.
	matched := tmpl matchUri: 'http://example.com/docs/file'.
	self assert: matched notNil.
	self assert: (matched at: 'dir') equals: 'docs'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'dir' -> 'docs').
	self assert: expanded equals: 'http://example.com/docs/file'.

	tmpl := McpUriTemplate template: 'http://example.com/file{.ext}'.
	matched := tmpl matchUri: 'http://example.com/file.json'.
	self assert: matched notNil.
	self assert: (matched at: 'ext') equals: 'json'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'ext' -> 'json').
	self assert: expanded equals: 'http://example.com/file.json'
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testLevel3QueryParams [
	"Verify Level 3 query parameter expansion and extraction."

	| tmpl matched expanded |

	tmpl := McpUriTemplate template: 'http://example.com/search{?q}'.
	matched := tmpl matchUri: 'http://example.com/search?q=smalltalk'.
	self assert: matched notNil.
	self assert: (matched at: 'q') equals: 'smalltalk'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'q' -> 'smalltalk').
	self assert: expanded equals: 'http://example.com/search?q=smalltalk'.

	tmpl := McpUriTemplate template: 'http://example.com/search{?q}{&lang}'.
	matched := tmpl matchUri: 'http://example.com/search?q=smalltalk&lang=en'.
	self assert: matched notNil.
	self assert: (matched at: 'q') equals: 'smalltalk'.
	self assert: (matched at: 'lang') equals: 'en'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'q' -> 'smalltalk' with: 'lang' -> 'en').
	self assert: expanded equals: 'http://example.com/search?q=smalltalk&lang=en'
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testLevel3SemicolonParams [
	"Verify Level 3 semicolon matrix parameter extraction."

	| tmpl matched expanded |

	tmpl := McpUriTemplate template: 'http://example.com/res{;id}'.
	matched := tmpl matchUri: 'http://example.com/res;id=42'.
	self assert: matched notNil.
	self assert: (matched at: 'id') equals: '42'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'id' -> '42').
	self assert: expanded equals: 'http://example.com/res;id=42'
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testLevel4PathExplode [
	"Verify Level 4 path explode operator matching multi-segment values."

	| tmpl matched expanded |

	tmpl := McpUriTemplate template: 'http://example.com{/path*}'.
	matched := tmpl matchUri: 'http://example.com/one/two/three'.
	self assert: matched notNil.
	self assert: (matched at: 'path') equals: 'one/two/three'.

	expanded := tmpl expand: (EsOrderedDictionary with: 'path' -> 'one/two/three').
	self assert: expanded equals: 'http://example.com/one/two/three'
]

{ #category : 'Testing' }
TestMcpUriTemplateRfc6570 >> testPercentDecodingOnMatch [
	"Verify percent-encoded characters are unquoted when extracted from matched URIs."

	| tmpl matched |

	tmpl := McpUriTemplate template: 'http://example.com/items/{name}'.
	matched := tmpl matchUri: 'http://example.com/items/hello%20world'.
	self assert: matched notNil.
	self assert: (matched at: 'name') equals: 'hello world'
]
