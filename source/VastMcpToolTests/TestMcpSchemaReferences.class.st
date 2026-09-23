"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Deterministic, self-contained MCP 2.2.0 regression tests.
Fixtures own their state and do not contact external services.
"
Class {
	#name : 'TestMcpSchemaReferences',
	#superclass : 'TestCase',
	#category : 'VastMcpToolTests'
}

{ #category : 'Testing' }
TestMcpSchemaReferences >> testAnchor [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString:
        ('{"$defs":{"n":{"$anchor":"number","type":"integer"}},' ,
        '"properties":{"v":{"$ref":"#number"}}}').
    value := NeoJSONReader fromString: ('{"v":3}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testEmptyPropertyPointer [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"$defs":{"":{"type":"integer"}},' ,
        '"properties":{"v":{"$ref":"#/$defs/"}}}').
    value := NeoJSONReader fromString: ('{"v":3}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testEscapedPointer [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString:
        ('{"$defs":{"a/b~c":{"type":"integer"}},"type":"object",' ,
        '"properties":{"v":{"$ref":"#/$defs/a~1b~0c"}}}').
    value := NeoJSONReader fromString: ('{"v":3}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testFileReferenceRejected [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString:
        ('{"$ref":"file:///private/schema.json"}').
    value := NeoJSONReader fromString: ('{}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        Error

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testLocalPointer [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"type":"object",' ,
        '"properties":{"v":{"$ref":"#/$defs/number"}},' ,
        '"$defs":{"number":{"type":"integer"}}}').
    value := NeoJSONReader fromString: ('{"v":3}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testLocalPointerRejectsWrongType [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"type":"object",' ,
        '"properties":{"v":{"$ref":"#/$defs/number"}},' ,
        '"$defs":{"number":{"type":"integer"}}}').
    value := NeoJSONReader fromString: ('{"v":"bad"}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        McpJsonRpcError

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testMissingPointer [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"$ref":"#/$defs/missing"}').
    value := NeoJSONReader fromString: ('{}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        Error

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testNonProgressingCycleRejected [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"$ref":"#"}').
    value := NeoJSONReader fromString: ('{}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        Error

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testPercentEncodedPointer [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"$defs":{"a b":{"type":"integer"}},'
        ,
        '"properties":{"v":{"$ref":"#/$defs/a%20b"}}}').
    value := NeoJSONReader fromString: ('{"v":3}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testRecursiveObject [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString:
        ('{"type":"object","properties":{"child":{"$ref":"#"}}}').
    value := NeoJSONReader fromString: ('{"child":{"child":{}}}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testReferenceSiblingsEnforced [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"$ref":"#/$defs/item",' ,
        '"$defs":{"item":{"type":"object"}},"required":["v"]}').
    value := NeoJSONReader fromString: ('{}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        McpJsonRpcError

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testRelativeExternalReferenceRejected [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"$ref":"other.json"}').
    value := NeoJSONReader fromString: ('{}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        Error

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testRemoteReferenceRejected [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString:
        ('{"$ref":"https://example.invalid/schema"}').
    value := NeoJSONReader fromString: ('{}').
    self should: [McpSchemaValidator new validate: value against: schema] raise:
        Error

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testRootIdReference [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString:
        ('{"$id":"https://example.invalid/root",' ,
        '"$defs":{"n":{"type":"integer"}},' ,
        '"properties":{"v":{"$ref":"https://example.invalid/root#/$defs/n"}}}').
    value := NeoJSONReader fromString: ('{"v":2}').
    McpSchemaValidator new validate: value against: schema

]

{ #category : 'Testing' }
TestMcpSchemaReferences >> testUnusedExternalReferenceDoesNotFetch [
    "Exercise document-local reference behavior without any I/O."
    | schema value |
    schema := NeoJSONReader fromString: ('{"type":"object",' ,
        '"$defs":{"unused":{"$ref":"https://example.invalid/schema"}}}').
    value := NeoJSONReader fromString: ('{}').
    McpSchemaValidator new validate: value against: schema

]
