---
title: MCP Server
description: Accessing the MCP Server in COSMOS Enterprise
sidebar_custom_props:
  myEmoji: 👾
---

COSMOS Enterprise include an MCP Server that gives AI systems the ability to discover and interact with the COSMOS API.

:::warning[AI can be unpredictable and will send data to external servers. Use at your own risk.]

## Overview

The COSMOS MCP Server is available at `<Your COSMOS URL>/mcp`. It performs Automatic Oauth authentication with the client and will generally authenticate as the currently logged in COSMOS user in your web browser, or prompt you for a login if no one is currently logged in.

## Using with the Built-In AI Interface

COSMOS does not embed any AI agents or models. Nothing is bundled, nothing runs locally, and no AI functionality is available until you connect COSMOS to an LLM server that you provide. That means you must supply an external API key (or the URL of your own model server) before the Built-In AI Interface will do anything.

The Built-In AI Interface can be accessed by clicking the AI icon in the upper right-hand corner of COSMOS Enterprise. An Admin must configure a LLM Server using the Settings Gear icon, which includes entering the API key for the provider. Claude, Gemini, OpenAI, and OpenAI compatible LLMs can be used (including private model servers with an OpenAI-Compatible interface).

The built-in interface is aware of the MCP Server and will automatically use the exposed API methods when needed.

## Integrating with Claude Desktop

Goto Settings -> Developer and press the "Edit Config" button to discover the location of the claude_desktop_config.json. Edit this file and add the following section:

```
{
  "mcpServers": {
    "my-remote-server": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:2900/mcp", "--allow-http"]
    }
  }
}

```

Update localhost:2900 as needed.

## Integrating with Claude Code

At the command line run:

`claude mcp add --transport http openc3 http://localhost:2900/mcp`

Then start claude and run the following to authenticate:

`/mcp`

## Disabling the MCP Server

<span class="badge badge--secondary since-right">Since 7.2.1</span>
To disable the MCP Server entirely, set the following environment variable in
the `openc3-metrics` section of the `compose.override.yaml` file at the root of
your COSMOS Enterprise project and restart COSMOS:

```yaml
openc3-metrics:
  environment:
    # Prevent the launch of the MCP Server (also disable the in-app Chatbot
    # via Admin -> Settings). Any non-empty value disables it.
    - OPENC3_MCP_DISABLED=true
```

This prevents the MCP Server process from starting, so nothing listens at `/mcp`. Note that the Built-In AI Interface uses the MCP Server for all of its COSMOS interactions, so disabling the MCP Server also prevents the AI Interface from reading telemetry, sending commands, or running scripts. Remove the variable and restart COSMOS to re-enable.
