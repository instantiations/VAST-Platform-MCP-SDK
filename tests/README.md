# MCP Conformance Testing with VAST Smalltalk

This document describes how to execute the official [Model Context Protocol (MCP) Conformance Test Suite](https://github.com/modelcontextprotocol/conformance) (`@modelcontextprotocol/conformance`) against the VAST Smalltalk MCP SDK.

\---

## Table of Contents

- [MCP Conformance Testing with VAST Smalltalk](#mcp-conformance-testing-with-vast-smalltalk)
  - [Table of Contents](#table-of-contents)
  - [1. Overview \& Architecture](#1-overview--architecture)
  - [2. Prerequisites](#2-prerequisites)
  - [3. Server Conformance Testing](#3-server-conformance-testing)
    - [Step 1: Start the Conformance Server in VAST](#step-1-start-the-conformance-server-in-vast)
    - [Step 2: Run Server Tests via CLI](#step-2-run-server-tests-via-cli)
      - [Run All Server Scenarios](#run-all-server-scenarios)
      - [Run a Single Server Scenario](#run-a-single-server-scenario)
  - [4. Client Conformance Testing](#4-client-conformance-testing)
    - [Approach A: Interactive In-Image Testing (Quickest)](#approach-a-interactive-in-image-testing-quickest)
    - [Approach B: Automated CLI Testing via Headless VAST Image](#approach-b-automated-cli-testing-via-headless-vast-image)
      - [1. Package a Headless Console Image](#1-package-a-headless-console-image)
      - [2. Run the Test Harness](#2-run-the-test-harness)
  - [5. Troubleshooting \& Debugging](#5-troubleshooting--debugging)
    - [Inspecting Check Details](#inspecting-check-details)
    - [Verbose Mode](#verbose-mode)
    - [Stale Baseline Entries](#stale-baseline-entries)
    - [Localhost Rebinding Warnings](#localhost-rebinding-warnings)

\---

## 1\. Overview \& Architecture

The official test harness evaluates MCP implementations against the protocol specification:

```
                  ┌────────────────────────────────────────────────────────┐
                  │          @modelcontextprotocol/conformance             │
                  └────────────────────────────────────────────────────────┘
                                    │                           ▲
                  1. Server Mode    │                           │  2. Client Mode
                                    ▼                           │
                        ┌───────────────────────┐   ┌───────────────────────┐
                        │  McpConformanceServer │   │  McpConformanceClient │
                        │   (Streamable HTTP)   │   │  (Runs requested test)│
                        │ http://localhost:3000 │   │                       │
                        └───────────────────────┘   └───────────────────────┘
```

* **Server Testing Mode (`--mode server`):** The VAST HTTP server runs locally. The test runner connects to it over Streamable HTTP and verifies its handling of tools, resources, prompts, completions, SSE response streams, and DNS rebinding protection.
* **Client Testing Mode (`--mode client`):** The test runner spins up its own mock server on an ephemeral port, exports scenario parameters via environment variables, and executes your client process.

\---

## 2\. Prerequisites

1. **VAST Platform Smalltalk 15+** with the `MCP SDK` configuration map loaded.
2. **Node.js 20+** and `npm` installed on your machine.
3. Access to `npx` (comes bundled with Node.js).

\---

## 3\. Server Conformance Testing

### Step 1: Start the Conformance Server in VAST

In a VAST Smalltalk Workspace, execute:

```smalltalk
"Start the conformance server on port 3000 (default) or any chosen port"
server := McpConformanceServer startOnPort: 3000.

"Check status"
Transcript show: 'Conformance server running at: ' , server url; cr.
```

*(To restart the server if you change fixtures or code: `server restart`)*

### Step 2: Run Server Tests via CLI

Open a terminal in the `./tests` directory and run:

#### Run All Server Scenarios

```bash
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --expected-failures ./conformance-baseline.yml
```

#### Run a Single Server Scenario

```bash
# 1. Simple text tool execution
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --scenario tools-call-simple-text

# 2. Tool execution with SSE streaming progress updates (0%, 50%, 100%)
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --scenario tools-call-with-progress

# 3. Localhost DNS rebinding protection (Host \\\& Origin validation)
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --scenario dns-rebinding-protection

# 4. Modern SEP-2322 MRTR input-required elicitation retry
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --scenario input-required-result-basic-elicitation

# 5. Concurrent POST requests on the same session
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --scenario server-sse-multiple-streams \\\\
  --expected-failures ./conformance-baseline.yml
```

\---

## 4\. Client Conformance Testing

The SDK provides `McpConformanceClient` to execute client scenarios.

### Approach A: Interactive In-Image Testing (Quickest)

You can run any client scenario directly against your running `McpConformanceServer` from a VAST Workspace without requiring external process packaging:

```smalltalk
"Run the complete client conformance suite with Transcript progress and summary"
McpConformanceClient runAllOnUrl: 'http://127.0.0.1:3000/mcp'.
```

**Output in Transcript:**

```
=======================================================
Running MCP Client Conformance Suite against: http://127.0.0.1:3000/mcp
=======================================================
  \\\[PASS] initialize
  \\\[PASS] tools-call
  \\\[PASS] request-metadata
  \\\[PASS] sep-2322-client-request-state
  \\\[PASS] elicitation-defaults
  \\\[PASS] json-schema-2020-12-preservation
-------------------------------------------------------
Results: 6/6 scenarios passed.
=======================================================
```

You can also run individual scenarios and inspect their structured results:

```smalltalk
result := McpConformanceClient runScenario: 'tools-call' onUrl: 'http://127.0.0.1:3000/mcp'.
result := McpConformanceClient runScenario: 'sep-2322-client-request-state' onUrl: 'http://127.0.0.1:3000/mcp'.
```

\---

### Approach B: Automated CLI Testing via Headless VAST Image

To have the official `@modelcontextprotocol/conformance` runner drive the client:

#### 1\. Package a Headless Console Image

Using the **VAST Packager (`EpPackager`)**:

1. Create a packaging specification.
2. Set the startup class (`startUpClass`) to **`McpConformanceClient`**.  
*(When VAST starts up, it automatically invokes `McpConformanceClient class>>run`, which calls `main`).*
3. Package as a console application, e.g., `mcp-conformance-client.icx`.

#### 2\. Run the Test Harness

**On Windows:**

```bash
npx @modelcontextprotocol/conformance client \\\\
  --command "C:\\\\path\\\\to\\\\es.exe -iC:\\\\path\\\\to\\\\mcp-conformance-client.icx -nouistart" \\\\
  --scenario initialize
```

**On Linux:**

```bash
npx @modelcontextprotocol/conformance client \\\\
  --command "/opt/vast/bin/es -i/path/to/mcp-conformance-client.icx -nouistart" \\\\
  --scenario initialize
```

**Run the entire client suite:**

```bash
npx @modelcontextprotocol/conformance client \\\\
  --command "es.exe -imcp-conformance-client.icx -nouistart" \\\\
  --suite all \\\\
  --expected-failures ./conformance-baseline.yml
```

## 5\. Troubleshooting \& Debugging

### Inspecting Check Details

When a scenario fails, the test runner outputs a structured record to disk:

```bash
cat results/server-<scenario-name>-\\\*/checks.json
```

This file contains the exact HTTP status codes, wire headers, and error messages returned by both the server and the test harness.

### Verbose Mode

Pass `--verbose` to the CLI to stream all JSON-RPC request and response payloads to the console:

```bash
npx @modelcontextprotocol/conformance server \\\\
  --url http://127.0.0.1:3000/mcp \\\\
  --scenario tools-call-with-progress \\\\
  --verbose
```

### Stale Baseline Entries

The conformance harness enforces an anti-staleness rule:

```
Stale baseline entries (now passing - remove from baseline):
  ? <scenario-name>
```

If an optional extension or deprecated scenario starts passing (as `ping` does in this SDK), **remove that line from `conformance-baseline.yml`**; otherwise, the harness will exit with code `1`.

### Localhost Rebinding Warnings

DNS rebinding protection requires that your server accept `localhost`, `127.0.0.1`, and `\\\[::1]`. If running through a custom domain or Docker bridge, configure `allowedHosts:` explicitly on `McpHttpServer`.
