# ZapierSDK

[![Hex.pm](https://img.shields.io/hexpm/v/zapier_sdk.svg)](https://hex.pm/packages/zapier_sdk)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/zapier_sdk)

Zapier's [SDK](https://docs.zapier.com/sdk) gives you programmatic access to
9,000+ app integrations without building OAuth for any of them. It ships as a
TypeScript package. This is the Elixir version.

It's a plain HTTP client, so there's no Node.js, no npm install, and no CLI
running in a subprocess. It calls the same API the official SDK does, and
everything is ordinary Elixir underneath: actions run in your process, results
implement `Enumerable`, failures come back as tagged tuples.

Unofficial and not affiliated with Zapier.

> Zapier's SDK is in open beta and free while it lasts. Enterprise accounts are
> opted out by default. Check the [docs](https://docs.zapier.com/sdk) for where
> things stand.

## Install

```elixir
def deps do
  [
    {:zapier_sdk, "~> 0.2"}
  ]
end
```

## Getting credentials

Auth is OAuth client credentials, the same thing the official SDK uses to run
[without a browser login](https://docs.zapier.com/sdk/deploy). You make a pair
once using [Zapier's CLI](https://docs.zapier.com/sdk/using-the-cli):

```bash
npx @zapier/zapier-sdk-cli login
npx @zapier/zapier-sdk-cli create-client-credentials
```

Copy the secret when it appears. Zapier only shows it once, and if you lose it
your only option is to delete the credential and make another.

```elixir
config :zapier_sdk,
  client_id: System.get_env("ZAPIER_CREDENTIALS_CLIENT_ID"),
  client_secret: System.get_env("ZAPIER_CREDENTIALS_CLIENT_SECRET")
```

Leave those out and the SDK reads `ZAPIER_CREDENTIALS_CLIENT_ID` and
`ZAPIER_CREDENTIALS_CLIENT_SECRET` from the environment instead. Those are the
same names the TypeScript SDK looks for, so if you already have a deployment
configured for it, this works there with no changes. Zapier's
[deploy guide](https://docs.zapier.com/sdk/deploy) covers Railway, Vercel,
GitHub Actions, GitLab CI, and AWS.

Tokens get fetched on first use and refreshed before they expire. You don't
have to think about it.

Hacking on something throwaway? You can hand it a bearer token directly with
`config :zapier_sdk, token: "..."` (or `ZAPIER_CREDENTIALS`). That one never
refreshes, so don't ship it.

## Finding your connections

A connection is one authenticated link between your Zapier account and one app.
Every action runs through one, so you need at least one before anything useful
happens. Connect apps at
[zapier.com/app/assets/connections](https://zapier.com/app/assets/connections),
then list what you've got:

```elixir
{:ok, connections} = ZapierSDK.list_connections()

Enum.each(connections, fn c ->
  IO.puts("#{c["id"]}  #{c["app_key"]}  #{c["title"]}")
end)
```

The IDs are UUIDs. Give names to the ones you reach for often:

```elixir
config :zapier_sdk, connections: [
  drive:    {"google-drive",        "00000000-0000-0000-0000-000000000000"},
  slack:    {"slack",               "00000000-0000-0000-0000-000000000000"},
  jira:     {"jira-software-cloud", "00000000-0000-0000-0000-000000000000"},
  calendar: {"google-calendar",     "00000000-0000-0000-0000-000000000000"}
]
```

Or skip the config and build one on the spot:

```elixir
conn = ZapierSDK.connection("google-drive", "02069fbe-9c91-81c1-8567-8ee2dbb7ad64")
{:ok, result} = ZapierSDK.search(conn, "file_v2", %{"title" => "budget"})
```

## Doing something

```elixir
# Search Google Drive
{:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "Q3 budget"})

for file <- result do
  IO.puts(file["title"])
end

# Post to Slack
{:ok, _} = ZapierSDK.write(:slack, "channel_message", %{
  "channel" => "#engineering",
  "text" => "Deploy complete"
})
```

That's most of the API. `search/4`, `read/4`, and `write/4` cover the common
cases, and `run/3` takes an `Action` struct when you need a type they don't
wrap.

## Things that will trip you up

None of these are this library's doing. They're how Zapier's catalog works, and
each one fails in a way the error message alone won't explain.

**An action's type is part of its name.** Slack has a `channel_message` you
write and a `channel_message` you read, and they're different actions. Calling
`search/4` on a write action doesn't do something approximate, it gets rejected.

**You can't guess input field names.** Slack's message body is `text`, not
`message`. A DM's recipient goes in `channel`, not `user`. Google Calendar wants
`calendarid`, `start_time`, and `end_time`. Look them up, don't assume.

**Slugs move, keys don't.** Coda's actions still live under the key
`CodaCLIAPI`, but its slug is now `superhuman-docs`. If an app you're sure
exists won't resolve, try its key.

**Connections expire.** OAuth grants lapse, and when one does every action
against it fails until you reconnect the app in Zapier. You'll get
`%Error{type: :connection_expired}` rather than a confusing empty result.

The CLI is the fastest way to answer the first two:

```bash
npx @zapier/zapier-sdk-cli list-actions google-drive --action-type search
npx @zapier/zapier-sdk-cli list-input-fields google-drive search file_v2
```

Same thing from Elixir, if you'd rather stay in IEx:

```elixir
{:ok, apps}    = ZapierSDK.list_apps(search: "google")
{:ok, actions} = ZapierSDK.list_actions("google-drive", action_type: "search")
```

And when you get a key wrong, the error tells you what was available:

```elixir
{:error, error} = ZapierSDK.search(:drive, "find_file", %{})
error.type     #=> :action_not_found
error.details  #=> ["file_or_folder_by_id", "file_permissions", "file_v2", "folder_v2"]
```

## When things go wrong

Nothing raises. You get `{:ok, %Result{}}` or `{:error, %ZapierSDK.Error{}}`,
and the error has a `type` you can match on:

```elixir
case ZapierSDK.search(:jira, "issue_key", %{"issue_key" => "PROJ-1"}) do
  {:ok, result} ->
    result.data

  {:error, %ZapierSDK.Error{type: :connection_expired}} ->
    # OAuth grant lapsed. Reconnect the app in Zapier.
    :needs_reconnect

  {:error, %ZapierSDK.Error{type: :rate_limited} = error} ->
    Process.sleep(error.retry_after_ms || 1_000)
    :retry

  {:error, error} ->
    Logger.error(Exception.message(error))
end
```

One thing worth being explicit about: if a run finishes but the integration
reported problems, that's an error here, not an empty success. An expired Jira
connection gives you `%Error{type: :connection_expired}`, never
`{:ok, %Result{count: 0}}`. A silent empty list is the worst possible answer to
"did that work?", so you won't get one.

The full set:

| `type` | Meaning |
|---|---|
| `:no_credentials` | Nothing configured to authenticate with |
| `:authentication_failed` | Token exchange rejected, or the API returned 401 |
| `:connection_expired` | The app connection needs reconnecting |
| `:action_failed` | The integration returned errors |
| `:app_not_found` / `:action_not_found` | Unknown app or action key |
| `:rate_limited` | 429; see `:retry_after_ms` |
| `:timeout` | The run didn't finish in time |
| `:http_error` / `:transport_error` | Other HTTP or network failure |

## Running a lot at once

Actions run in whatever process calls them, so getting concurrency is mostly a
matter of starting more processes. There are two helpers for the usual shapes:

```elixir
# Fire one off and collect it later
task = ZapierSDK.async(:drive, :search, "file_v2", %{"title" => "notes"})
{:ok, result} = Task.await(task, 60_000)

# Run a batch, get results back in the order you asked for
alias ZapierSDK.Action

results = ZapierSDK.run_many([
  {:drive, Action.search("file_v2", %{"title" => "notes"})},
  {:slack, Action.search("message", %{"query" => "deploy"})}
], max_concurrency: 4)

Enum.each(results, fn
  {:ok, result} -> IO.puts("#{result.count} items in #{result.elapsed_ms}ms")
  {:error, err} -> IO.puts("failed: #{Exception.message(err)}")
end)
```

## Pages

`run/3` follows Zapier's cursor and hands back everything. If "everything" is
more than you want, cap it:

```elixir
{:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "report"}, max_items: 50)
```

Or stream it, which only fetches a page when you actually need one:

```elixir
ZapierSDK.stream(:drive, "file_v2", %{"title" => "report"})
|> Stream.take(5)
|> Enum.each(&IO.inspect/1)
```

Streams raise on failure instead of returning an error tuple, because there's
nowhere in a stream to put one. If you'd rather match on errors, use `search/4`.

## App helpers

Thin wrappers for a handful of integrations, with the action and field names
already filled in correctly:

```elixir
alias ZapierSDK.Apps.{GoogleDrive, Slack, GoogleCalendar, Jira, Coda}

{:ok, result} = GoogleDrive.find_file("Q3 budget")
{:ok, _}      = Slack.send_message("#general", "Hello!")
{:ok, result} = GoogleCalendar.today_events()
{:ok, result} = Jira.my_open_issues()
{:ok, rows}   = Coda.list_rows(doc_id, table_id)
```

Each one defaults to a named connection (`:drive`, `:slack`, `:calendar`,
`:jira`, `:coda`). Pass `connection:` to point it somewhere else.

## Telemetry

Everything is emitted under `[:zapier_sdk, :action]`:

| Event | Measurements | Metadata |
|---|---|---|
| `[:zapier_sdk, :action, :start]` | `system_time` | `connection`, `action` |
| `[:zapier_sdk, :action, :stop]` | `duration` | `connection`, `action`, `result` |
| `[:zapier_sdk, :action, :exception]` | `duration` | `connection`, `action`, `kind`, `reason` |

```elixir
:telemetry.attach("log-zapier", [:zapier_sdk, :action, :stop], fn _e, %{duration: d}, meta, _ ->
  ms = System.convert_time_unit(d, :native, :millisecond)
  Logger.info("#{meta.action.name} finished in #{ms}ms")
end, nil)
```

If you're counting failures, match on the result rather than listening for
`:exception`. A returned `{:error, _}` is a perfectly normal `:stop` event;
`:exception` only fires when something actually blew up.

## Testing

Every request goes through `Req`, so you can swap the transport for a stub and
never touch the network:

```elixir
# config/test.exs
config :zapier_sdk,
  req_options: [plug: {Req.Test, ZapierSDK}],
  token: "test-token",
  max_retries: 0
```

```elixir
test "finds a file" do
  Req.Test.stub(ZapierSDK, fn conn ->
    # respond to /api/v0/apps, /api/v0/actions, and the run endpoints
  end)

  assert {:ok, result} = ZapierSDK.search(:drive, "file_v2", %{"title" => "x"})
  assert result.count == 1
end
```

Stubbing three endpoints by hand gets old fast, so this project's own tests use
`ZapierSDK.ZapierStub`, which implements the whole protocol. Tests say what they
want the action to return and the stub handles the rest. Worth copying if you're
doing more than a couple of these.

If you're working on the SDK itself, `mix check` runs everything CI runs
(formatter, `mix compile --warnings-as-errors`, Credo, Dialyzer, the test
suite, and a check for retired/unused dependencies) in one shot.

## How it works

Running an action takes two round trips, not one. The SDK does both for you:

1. Resolve the app's versioned `implementation_id` and the action's internal
   ID. These only change when an app publishes a new version, so they're cached
   in ETS.
2. `POST` an action run, then poll it with backoff until it stops reporting
   `waiting`, following the cursor for as long as you want more results.

```text
ZapierSDK              ← Public API
├── Client             ← Action runs: create, poll, paginate
├── Catalog            ← App/action/connection metadata + ETS cache
├── Auth               ← OAuth client credentials, token cache + refresh
├── HTTP               ← Req transport, error mapping, retry policy
├── Connection         ← Named and ad-hoc connections
├── Action             ← Action structs and types
├── Result             ← Results (implements Enumerable)
├── Error              ← Typed errors
├── Config             ← Config and environment resolution
└── Apps/              ← Jira, Slack, GoogleDrive, GoogleCalendar, Coda
```

Two deliberate choices in there. Only idempotent requests get retried, so an
action run is never replayed: retrying "send a Slack message" sends it twice,
and that's worse than failing. And a 429 comes straight back to you with
`:retry_after_ms` attached rather than being slept on internally, because
Zapier's `Retry-After` can be half a minute and a call that quietly blocks that
long is indistinguishable from a hang.

## Zapier's docs

App keys, action keys, and field names are shared across every Zapier client,
so their docs apply here even though the examples are TypeScript:

- [Zapier SDK](https://docs.zapier.com/sdk) for the overview and beta status
- [Quickstart](https://docs.zapier.com/sdk/quickstart) if you want the official tour
- [API reference](https://docs.zapier.com/sdk/reference) for every method
- [Using the CLI](https://docs.zapier.com/sdk/using-the-cli) and the
  [CLI reference](https://docs.zapier.com/sdk/cli-reference) for `list-actions`,
  `list-input-fields`, and the rest
- [Deploy with client credentials](https://docs.zapier.com/sdk/deploy) for
  creating, storing, and rotating credentials
- [Your connections](https://zapier.com/app/assets/connections) to connect apps
  and fix expired ones

## License

MIT
