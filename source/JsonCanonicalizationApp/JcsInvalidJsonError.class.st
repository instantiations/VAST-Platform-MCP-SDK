"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# JcsInvalidJsonError

`JcsInvalidJsonError` signals JSON input that cannot participate in
canonicalization.

## Responsibilities

- Distinguish invalid JSON from ordinary configuration failures.
- Preserve the parser failure at the canonicalization boundary.

## Lifecycle and boundaries

The exception is immutable after signaling and owns no resources.
"
Class {
	#name : 'JcsInvalidJsonError',
	#superclass : 'Error',
	#category : 'JsonCanonicalizationApp'
}
