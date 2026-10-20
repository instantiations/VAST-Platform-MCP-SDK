Class {
	#name : 'McpResourceManager',
	#superclass : 'AcoResourceManager',
	#category : 'McpApp'
}

{ #category : 'ACO-API',
  #vaVisibility : 'private' }
McpResourceManager >> unlockThreadInProcess: aProcess release: release [

	| state |
	
	state := Processor enableAsyncMessages: false.
	super unlockThreadInProcess: aProcess release: release.
	Processor enableAsyncMessages: state.
]
