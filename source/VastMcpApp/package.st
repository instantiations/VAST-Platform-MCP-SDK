Package {
	#name : 'VastMcpApp',
	#vaPrerequisites : ['EsBase64CoderApp','EsUUIDApp','RegexCoreApp','VastJsonCanonicalizationApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'VastMcpPrompts',
			'VastMcpProtocol',
			'VastMcpResources',
			'VastMcpTools'
		]
	}
]
}
