Extension {
	#name : 'EsPendingEvents'
}

{ #category : 'ES-API',
  #vaVisibility : 'private' }
EsPendingEvents >> _schedule: dispatch [

	self isScheduled ifTrue: [^self].
	self assert: [self isEmpty not].
	self eventScheduled
		ifTrue: [
			self assert: [state == EsStateCancelled].
			state := EsStateCancelled.
			^self].
	state := EsStateScheduled.
	EsAsyncTaskScheduler scheduleTask: [| oldState |
		oldState := state.
		state := EsStateUnscheduled.
		oldState == EsStateCancelled ifFalse: [self handleNext: dispatch]].
]
