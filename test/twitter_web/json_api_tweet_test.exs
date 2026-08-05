defmodule TwitterWeb.JsonApiTweetTest do
  use TwitterWeb.ConnCase, async: true

  test "lists public tweet attributes and self links", %{conn: conn} do
    user =
      Ash.Seed.seed!(Twitter.Accounts.User, %{
        email: "json-api@example.com",
        hashed_password: "not-used-in-tests"
      })

    tweet =
      Ash.create!(Twitter.Tweets.Tweet, %{text: "from JSON:API"},
        action: :create,
        actor: user
      )

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/json/tweets")

    assert %{
             "data" => [
               %{
                 "id" => id,
                 "attributes" => %{"text" => "from JSON:API"},
                 "links" => %{"self" => self_link}
               }
             ]
           } = json_response(conn, 200)

    assert id == tweet.id
    assert self_link =~ "/api/json/tweets/#{tweet.id}"
  end
end
