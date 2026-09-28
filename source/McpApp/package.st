Package {
	#name : 'McpApp',
	#vaPrerequisites : ['EsBase64CoderApp','EsUUIDApp','RegexCoreApp','JsonCanonicalizationApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'McpPrompts',
			'McpProtocol',
			'McpResources',
			'McpTools'
		]
	}
]
}
