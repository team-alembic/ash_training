# Lab 11 - AshAi MCP Servers

## Relevant Documentation

- [AshAi.Mcp Documentation](https://hexdocs.pm/ash_ai/AshAi.Mcp.html)
- [Model Context Protocol Specification](https://spec.modelcontextprotocol.io/)
- [MCP Transport Specification](https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/transports/)

## Context

The Model Context Protocol (MCP) is a standardized way to expose tools and
context to AI assistants like Claude Code, Cursor, Zed, and Windsurf. AshAi
provides built-in MCP server support to expose your application's capabilities
to these tools.

In this lab, we'll set up two MCP servers:

1. **Development MCP Server** - For use with IDEs and development tools
2. **Application MCP Server** - Exposes only specific tools, such as reading the
   tweet feed

## Steps

### 1. Install AshAi Dependencies

Install AshAi using igniter:

```bash
mix igniter.install ash_ai
```

This will:

- Add `ash_ai` and its dependencies to `mix.exs`
- Set up the necessary configuration
- Install any required extensions
- **Automatically configure the development MCP server** at
  `http://localhost:4000/ash_ai/mcp`

The installer sets up the development MCP server for you.

### 2. Configure Development Tools

Start your server:

```bash
mix phx.server
```

The MCP server is available, but your AI coding tools need to know about it. The
configuration varies by tool:

#### Claude Code

```bash
claude mcp add --transport http ash_ai http://localhost:4000/ash_ai/mcp
```

#### For Zed

Add to your Zed settings (you'll need the mcp-proxy
https://hexdocs.pm/tidewave/mcp_proxy.html):

```json
{
  "tidewave-mcp": {
    "command": "/path/to/mcp-proxy",
    "args": ["http://localhost:$PORT/ash_ai/mcp"],
    "env": {}
  }
}
```

### 3. Test the Development MCP Server

Try to ask your agent which Ash resources we have in the project.

### 4. Define Tools in the Domain

Before we can expose tools via the MCP server, we need to define them in our
domain module. Tools are declarative definitions that map actions on resources
to callable functions.

Open `lib/twitter/tweets.ex` and add the AshAi extension and a `tools` block:

```elixir
defmodule Twitter.Tweets do
  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain, AshAdmin.Domain, AshAi]

  # ... existing resources block ...

  tools do
    tool :read_feed, Twitter.Tweets.Tweet, :feed do
      description "Retrieve the feed of tweets, sorted by most recent first"
    end
  end
end
```

Each tool definition:

- Has a unique name (`:read_feed`)
- Points to a resource (`Twitter.Tweets.Tweet`)
- Specifies an action (`:feed`)
- Includes a description for the AI to understand what the tool does, defaults
  to the actions description if not provided.

These tools can now be called by AI assistants and exposed via the MCP server.

### 5. Configure MIME Types for Event Streaming

MCP servers use Server-Sent Events (SSE) to stream responses, which requires the
`text/event-stream` content type. Phoenix needs to know about this MIME type.

Open `config/config.exs` and add the MIME type configuration:

```elixir
config :mime, :types, %{
  "application/vnd.api+json" => ["json"],
  "text/event-stream" => ["event-stream"]
}

config :mime, :extensions, %{
  "json" => "application/vnd.api+json",
  "event-stream" => "text/event-stream"
}
```

run `mix deps.compile --force mime`

This configures Phoenix to:

- Recognize `text/event-stream` as a valid content type
- Map it to the `event-stream` file extension
- Enable SSE support for streaming MCP responses

### 6. Set Up the Application MCP Server

The application MCP server allows you to expose specific tools to external AI
assistants. Unlike the development server, it gives you fine-grained control
over what's available.

First, create a pipeline in `lib/twitter_web/router.ex` that accepts both JSON
and event-stream content types:

```elixir
pipeline :mcp do
  plug :accepts, ["json", "event-stream"]
end
```

Then add a route for the application MCP server:

```elixir
scope "/api" do
  pipe_through :mcp

  scope "/mcp" do
    forward "/", AshAi.Mcp.Router,
      tools: [:read_feed],
      otp_app: :twitter
  end
end
```

This makes the application MCP server available at `/api/mcp` and exposes only
the `read_feed` tool. The tool is referenced using the domain module and tool
name from the `tools` block we just defined.

**Note:** Unlike the development MCP server which automatically exposes all Ash
resources and their actions, the application server only exposes the tools you
explicitly list in the `tools:` option. This gives you precise control over what
external AI assistants can access.

This training route is intentionally unauthenticated for local use. Before
deploying it, require authentication supported by your MCP clients (OAuth 2.1
or an API key), authorize the resulting actor, and add rate limiting. Limiting
the tool list is not an authentication mechanism.

The `:mcp` pipeline ensures both regular JSON requests and event-stream requests
are accepted, which is necessary for the MCP protocol to function properly.

### 7. Test the Application MCP Server

Start your Phoenix server:

```bash
mix phx.server
```

You can test the MCP server by connecting to it from an MCP client. The server
exposes the `read_feed` tool which retrieves the feed of tweets.

## Try on your own

Now that you understand the flow, add more tools to the MCP server:

1. **Define additional tools** in the `tools` block in `lib/twitter/tweets.ex`:
   - Add a `:read_tweet` tool that uses the `:read` action

2. **Expose these tools** via the application MCP server by adding them to the
   `tools:` list in the router

3. **Test** that the MCP server now exposes both tools by connecting to it
