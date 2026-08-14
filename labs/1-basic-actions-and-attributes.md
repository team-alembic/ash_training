# Lab 1 - Basic Actions and Attributes

## Relevant Documentation

- [Attributes](https://hexdocs.pm/ash/attributes.html)
- [Create Actions](https://hexdocs.pm/ash/create-actions.html)
- [Update Actions](https://hexdocs.pm/ash/update-actions.html)
- [Read Actions](https://hexdocs.pm/ash/read-actions.html)
- [Destroy Actions](https://hexdocs.pm/ash/destroy-actions.html)
- [Validations](https://hexdocs.pm/ash/validations.html)

## Existing setup

- A shell of a UI for tweets. This is very similar to what you get by running `mix ash_phoenix.gen.live`, but simplified for this training. We will go over this before the lab.

## Steps

1. run `mix ash.codegen add_tweets` to generate the required data migrations, then `mix ash.migrate` to run them. The `tweets` table already exists from Lab 0, so this migration just brings the database in line with the resource (it adds the timestamp columns).

2. Lets start by adding an empty `:create` action to `Twitter.Tweets.Tweet`.

```elixir
actions do
  ...
  create :create do
  end
end
```

Actions are public by default. If you ever want an action for internal use only, you can set `public? false` inside it to keep it out of API extensions like GraphQL and JSON:API — we'll rely on the default here.

3. Now, we're going to handle the creation in the UI. Add this to your `lib/twitter_web/live/tweet_live/form.ex`.

Replace this code:

```elixir
# we're creating a tweet. Create logic goes here.
{:error, "Create not implemented"}
```

with this code:

```elixir
Twitter.Tweets.Tweet
|> Ash.Changeset.for_create(:create, params["tweet"] || %{}, actor: socket.assigns.current_user)
|> Ash.create()
```

Notice how this extracts params from the input. Right now we aren't using any params but this sets us up for the next step.
Additionally, this passes the current user in to the changeset. Don't worry about this for now.

4. Now you can create a new empty tweet! To try it out at localhost:4000, create an account and create an empty tweet.

5. Next, let's add a `:text` attribute that is a `:string`, so that we can see what users are tweeting. You may have already done this in lab 0!

```elixir
attribute :text, :string
```

6. This updates our application, but not the underlying database. To do that, we have to generate and run migrations.
   Run `mix ash.codegen add_text_to_tweet` to generate the required migrations, and then `mix ash.migrate` to apply them.

7. Make your `:create` accept `:text` in `Twitter.Tweets.Tweet`.

```elixir
accept [:text]
```

8. Add the following inside of the `<.form>`, above the `<footer>` element in `lib/twitter_web/live/tweet_live/form.ex`.

```heex
<.input label="Text" type="textarea" name="tweet[text]" value={@tweet && @tweet.text} />
```

Now you can create a tweet with some text!

9. To show this in the table view, we'll add a column for it in `tweet_live/index.ex`, underneath the id column.

```heex
<:col :let={{_id, tweet}} label="Text">
  {tweet.text}
</:col>
```

10. Next, add an `:update` action that accepts the `:text` as well.

11. And add a handler for it in `lib/twitter_web/live/tweet_live/form.ex`.

Notice how the existing code for handling a `create` passes in the resource `Twitter.Tweets.Tweet` as its first argument.
For updates, however, we pass the record being updated.

Replace this code:

```elixir
# we're updating a tweet. Update logic goes here.
{:error, "Update not implemented"}
```

with this code:

```elixir
socket.assigns.tweet
|> Ash.Changeset.for_update(:update, params["tweet"] || %{}, actor: socket.assigns.current_user)
|> Ash.update()
```

12. The `:destroy` action was generated in Lab 0, so deleting tweets now works
    without any additional resource changes.

## Try on your own

- Add another text attribute, like `:label` or `:category`, and allow it to be added in the form. Add a column for it in the index view.

- Require that the `:text` attribute is not `nil`. The simplest way is `validate present(:text)` in your `:create` and `:update` actions. If you instead set `allow_nil? false` on the attribute, the generated migration adds a NOT NULL constraint — it will fail to run if any empty tweets exist (you created one in step 4!), so delete those first.

- Limit tweet length: add `validate byte_size(:text, max: 280)` to your `:create` and `:update` actions, then try submitting a longer tweet and observe the error. Bonus: combine it with `present(:text)` using `all([...])`
