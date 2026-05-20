---
title: MCP Server
description: Accessing the MCP Server in COSMOS Enterprise
sidebar_custom_props:
  myEmoji: 👾
---

COSMOS Enterprise include an MCP Server that gives AI systems the ability to discover and interact with the COSMOS API.

:::warning[AI can be unpredictable and will send data to external servers. Use at your own risk.]

## Overview

The COSMOS MCP Server is available at `<Your COSMOS URL>/mcp`. It performs Automatic Oauth authenication with the client and will generally authenticate as the currently logged in COSMOS user in your web browswer, or prompt you for a login if no one is currently logged in.

## Using with the Built-In AI Interface

The Built-In AI Interface can be accessed by clicking the AI icon in the upper right-hand corner of COSMOS Enterprise. An Admin must configure a LLM Server using the Settings Gear icon. Claude, Gemini, OpenAI, and OpenAI compatible LLMs can be used (including private model servers with an OpenAI-Compatible interface).

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

`claude mcp add openc3 http://localhost:2900/mcp`

Then start claude and run the following to authenticate:

`/mcp`
