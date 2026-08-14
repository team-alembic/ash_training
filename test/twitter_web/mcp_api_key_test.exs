defmodule TwitterWeb.McpApiKeyTest do
  use TwitterWeb.ConnCase, async: true

  setup do
    user =
      Ash.Seed.seed!(Twitter.Accounts.User, %{
        email: "mcp@example.com",
        hashed_password: "not-used-in-tests"
      })

    api_key =
      Ash.create!(
        Twitter.Accounts.ApiKey,
        %{user_id: user.id, expires_at: DateTime.add(DateTime.utc_now(), 1, :day)},
        authorize?: false
      )

    %{user: user, api_key: api_key.__metadata__.plaintext_api_key}
  end

  test "rejects requests without an API key", %{conn: conn} do
    conn = mcp(conn, nil, nil, "initialize", initialize_params())

    assert conn.status == 401
  end

  test "rejects an unknown API key", %{conn: conn} do
    conn = mcp(conn, "twitter_not_a_real_key", nil, "initialize", initialize_params())

    assert conn.status == 401
  end

  test "runs Lua scripts as the API key's user", %{conn: conn, user: user, api_key: api_key} do
    tweet =
      Ash.create!(Twitter.Tweets.Tweet, %{text: "like me over MCP"},
        action: :create,
        actor: user
      )

    init = mcp(conn, api_key, nil, "initialize", initialize_params())
    assert init.status == 200
    [session_id] = get_resp_header(init, "mcp-session-id")

    script = ~s|return likes.like({ input = { tweet_id = "#{tweet.id}" } })|

    call =
      mcp(build_conn(), api_key, session_id, "tools/call", %{
        name: "ash_lua_eval",
        arguments: %{input: %{script: script}}
      })

    assert call.status == 200
    refute call.resp_body =~ ~s("isError":true)

    assert [like] = Ash.read!(Twitter.Tweets.Like, authorize?: false)
    assert like.user_id == user.id
    assert like.tweet_id == tweet.id
  end

  defp mcp(conn, api_key, session_id, method, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> then(&if api_key, do: put_req_header(&1, "authorization", "Bearer #{api_key}"), else: &1)
    |> then(&if session_id, do: put_req_header(&1, "mcp-session-id", session_id), else: &1)
    |> post("/api/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method, params: params}))
  end

  defp initialize_params do
    %{
      protocolVersion: "2025-06-18",
      capabilities: %{},
      clientInfo: %{name: "test", version: "0.0.0"}
    }
  end
end
