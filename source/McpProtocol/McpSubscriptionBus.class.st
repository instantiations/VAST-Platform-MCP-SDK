"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSubscriptionBus

`McpSubscriptionBus` provides an in-memory pub-sub event bus for MCP change
notifications (SEP-2575).

## Responsibilities

- Manage active listener subscriptions with topic filters (`tools`, `prompts`,
  `resources`, `resourceSubscriptions`).
- Fan out change notifications (`publishToolsListChanged`,
  `publishPromptsListChanged`, `publishResourcesListChanged`,
  `publishResourceUpdated:`) to matching listeners.
- Ensure thread-safe registration, deregistration, and delivery.

## Lifecycle and boundaries

Owned by an `McpServer`. Subscriptions remain active until unsubscribed or
when their associated session/stream terminates.
"
Class {
	#name : 'McpSubscriptionBus',
	#superclass : 'Object',
	#instVars : [
		'subscribers',
		'subscribersMutex'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpSubscriptionBus class >> new [
	"Answer a new initialized subscription bus.

	 Answers:
		<McpSubscriptionBus>."

	^super new initialize
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpSubscriptionBus >> initialize [
	"Initialize subscription state and concurrency lock.

	 Answers:
		<McpSubscriptionBus> the receiver."

	super initialize.
	subscribers := OrderedCollection new.
	subscribersMutex := Semaphore forMutualExclusion.
	^self
]

{ #category : 'Protocol Operations' }
McpSubscriptionBus >> publishPromptsListChanged [
	"Broadcast a prompts list changed notification to interested subscribers.

	 Answers:
		<McpSubscriptionBus> the receiver."

	| targets |

	self subscribersMutex critical: [
		targets :=
			self subscribers select: [:each | | filter |
				filter := each at: 'filter' ifAbsent: [EsOrderedDictionary new].
				((filter at: 'promptsListChanged' ifAbsent: [false]) == true)
					or: [(filter at: 'prompts' ifAbsent: [false]) == true]]].
	targets do: [:each |
		[
			(each at: 'callback')
				cull: 'notifications/prompts/list_changed'
				cull: EsOrderedDictionary new]
					on: Error
					do: [:err | err return: nil]].
	^self
]

{ #category : 'Protocol Operations' }
McpSubscriptionBus >> publishResourceUpdated: aResourceUri [
	"Broadcast a resource updated notification for a specific URI to interested subscribers.

	 Arguments:
		aResourceUri - <String> URI of the updated resource.
	 Answers:
		<McpSubscriptionBus> the receiver."

	| targets params |

	params := EsOrderedDictionary with: 'uri' -> aResourceUri.
	self subscribersMutex critical: [
		targets :=
			self subscribers select: [:each | | filter uris |
				filter := each at: 'filter' ifAbsent: [EsOrderedDictionary new].
				uris := filter at: 'resourceSubscriptions' ifAbsent: [#()].
				(filter at: 'resources' ifAbsent: [false]) == true or: [uris includes: aResourceUri]]].
	targets do: [:each |
		[(each at: 'callback') cull: 'notifications/resources/updated' cull: params]
			on: Error
			do: [:err | err return: nil]].
	^self
]

{ #category : 'Protocol Operations' }
McpSubscriptionBus >> publishResourcesListChanged [
	"Broadcast a resources list changed notification to interested subscribers.

	 Answers:
		<McpSubscriptionBus> the receiver."

	| targets |

	self subscribersMutex critical: [
		targets :=
			self subscribers select: [:each | | filter |
				filter := each at: 'filter' ifAbsent: [EsOrderedDictionary new].
				((filter at: 'resourcesListChanged' ifAbsent: [false]) == true)
					or: [(filter at: 'resources' ifAbsent: [false]) == true]]].
	targets do: [:each |
		[
			(each at: 'callback')
				cull: 'notifications/resources/list_changed'
				cull: EsOrderedDictionary new]
					on: Error
					do: [:err | err return: nil]].
	^self
]

{ #category : 'Protocol Operations' }
McpSubscriptionBus >> publishToolsListChanged [
	"Broadcast a tools list changed notification to interested subscribers.

	 Answers:
		<McpSubscriptionBus> the receiver."

	| targets |

	self subscribersMutex critical: [
		targets :=
			self subscribers select: [:each | | filter |
				filter := each at: 'filter' ifAbsent: [EsOrderedDictionary new].
				((filter at: 'toolsListChanged' ifAbsent: [false]) == true)
					or: [(filter at: 'tools' ifAbsent: [false]) == true]]].
	targets do: [:each |
		[
			(each at: 'callback')
				cull: 'notifications/tools/list_changed'
				cull: EsOrderedDictionary new]
					on: Error
					do: [:err | err return: nil]].
	^self
]

{ #category : 'Registration' }
McpSubscriptionBus >> subscribe: aFilter callback: aBlock [
	"Register a new subscription callback with a filter.

	 Arguments:
		aFilter - <KeyedCollection> filter containing boolean flags or resource URIs.
		aBlock - <Block> [:method :params | ...] callback block.
	 Answers:
		<KeyedCollection> subscription entry."

	| entry |

	entry :=
		EsOrderedDictionary new
			at: 'filter' put: (aFilter ifNil: [EsOrderedDictionary new]);
			at: 'callback' put: aBlock;
			yourself.
	self subscribersMutex critical: [self subscribers add: entry].
	^entry
]

{ #category : 'Accessing' }
McpSubscriptionBus >> subscribers [
	"Answer the active subscribers collection.

	 Answers:
		<OrderedCollection>."

	subscribers ifNil: [subscribers := OrderedCollection new].
	^subscribers
]

{ #category : 'Accessing' }
McpSubscriptionBus >> subscribersCount [
	"Answer the number of active subscribers.

	 Answers:
		<Integer>."

	self subscribersMutex critical: [^self subscribers size]
]

{ #category : 'Accessing' }
McpSubscriptionBus >> subscribersMutex [
	"Answer the mutex protecting subscriber registrations.

	 Answers:
		<Semaphore>."

	subscribersMutex ifNil: [subscribersMutex := Semaphore forMutualExclusion].
	^subscribersMutex
]

{ #category : 'Registration' }
McpSubscriptionBus >> unsubscribe: aSubscriptionEntry [
	"Deregister an existing subscription.

	 Arguments:
		aSubscriptionEntry - <KeyedCollection> handle returned by subscribe:callback:.
	 Answers:
		<McpSubscriptionBus> the receiver."

	self subscribersMutex critical: [self subscribers remove: aSubscriptionEntry ifAbsent: []].
	^self
]
