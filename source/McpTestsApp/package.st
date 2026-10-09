Package {
	#name : 'McpTestsApp',
	#vaPrerequisites : ['EsAsynchronousSupport','McpApp','SUnit'],
	#vaSubApplications : [
	{
		#condition : 'true',
		#subapps : [
			'McpPromptTests',
			'McpProtocolTests',
			'McpResourceTests',
			'McpStructuralTests',
			'McpToolTests'
		]
	}
]
}
