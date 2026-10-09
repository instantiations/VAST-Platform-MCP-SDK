Class {
	#name : 'TestMcpPathSecurity',
	#superclass : 'TestCase',
	#category : 'McpResourceTests'
}

{ #category : 'Testing' }
TestMcpPathSecurity >> testContainsPathTraversal [
	"Verify path traversal detection across various directory escape patterns."

	self assert: (McpPathSecurity containsPathTraversal: '../etc/passwd').
	self assert: (McpPathSecurity containsPathTraversal: 'sub/../../secret').
	self assert: (McpPathSecurity containsPathTraversal: '..').
	self assert: (McpPathSecurity containsPathTraversal: 'dir\..\file').
	self assert:
		(McpPathSecurity containsPathTraversal: 'null' , ((Character value: 0) asString) , 'byte').

	self deny: (McpPathSecurity containsPathTraversal: 'normal/path/file.txt').
	self deny: (McpPathSecurity containsPathTraversal: 'file..name.txt').
	self deny: (McpPathSecurity containsPathTraversal: 'sub/dir')
]

{ #category : 'Testing' }
TestMcpPathSecurity >> testIsAbsolutePath [
	"Verify absolute path detection across POSIX and Windows formats."

	self assert: (McpPathSecurity isAbsolutePath: '/etc/passwd').
	self assert: (McpPathSecurity isAbsolutePath: '\Windows\System32').
	self assert: (McpPathSecurity isAbsolutePath: 'C:\Windows').
	self assert: (McpPathSecurity isAbsolutePath: 'd:/data').

	self deny: (McpPathSecurity isAbsolutePath: 'relative/path').
	self deny: (McpPathSecurity isAbsolutePath: 'file.txt').
	self deny: (McpPathSecurity isAbsolutePath: 'sub\file.txt')
]

{ #category : 'Testing' }
TestMcpPathSecurity >> testSafeJoin [
	"Verify safeJoin allows clean relative paths and rejects directory traversal or absolute escapes."

	| joined |

	joined := McpPathSecurity safeJoin: '/data/docs' with: 'readme.txt'.
	self assert: joined equals: '/data/docs/readme.txt'.

	joined := McpPathSecurity safeJoin: '/data/docs/' with: 'sub/readme.txt'.
	self assert: joined equals: '/data/docs/sub/readme.txt'.

	self
		should: [McpPathSecurity safeJoin: '/data/docs' with: '../etc/passwd']
		raise: McpPathEscapeError.
	self
		should: [McpPathSecurity safeJoin: '/data/docs' with: '/etc/passwd']
		raise: McpPathEscapeError.
	self
		should: [McpPathSecurity safeJoin: '/data/docs' with: 'C:\Windows']
		raise: McpPathEscapeError.
	self
		should: [
			McpPathSecurity safeJoin: '/data/docs' with: 'file' , ((Character value: 0) asString)]
		raise: McpPathEscapeError
]
