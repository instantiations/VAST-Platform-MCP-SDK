Package {
	#name : 'VastMcpTestsApp',
	#vaPrerequisites : ['EsAsynchronousSupport','SUnit','VastMcpApp'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'VastMcpPromptTests',
			'VastMcpProtocolTests',
			'VastMcpResourceTests',
			'VastMcpStructuralTests',
			'VastMcpToolTests'
		]
	}
]
}
