Package {
	#name : 'McpApp',
	#vaPrerequisites : ['EsBase64CoderApp','EsUUIDApp','JsonCanonicalizationApp','RegexCoreApp'],
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
