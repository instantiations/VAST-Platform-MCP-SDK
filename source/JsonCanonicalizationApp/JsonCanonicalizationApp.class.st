"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# VastJsonCanonicalizationApp

`VastJsonCanonicalizationApp` defines the loadable module for JSON
Canonicalization Scheme support.

## Responsibilities

- Own deterministic JSON parsing and canonical byte generation.
- Reject invalid JSON and avoid locale or image-dependent formatting.

## Lifecycle

The VAST application loader owns module initialization and unloading.
Runtime objects are owned by the services that create them.
"
Class {
	#name : 'JsonCanonicalizationApp',
	#superclass : 'Application',
	#category : 'JsonCanonicalizationApp'
}
