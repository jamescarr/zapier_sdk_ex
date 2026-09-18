# Changelog

## v0.2.0

Rewritten as a native HTTP SDK. The previous release shelled out to the Zapier
SDK CLI; it no longer does, and no longer works against the current API.

### Breaking

* **No Node.js dependency.** The SDK now calls the Zapier SDK API over HTTP
  directly. `npm install` and `npx` are gone.
* **Authentication is now required and explicit.** Configure OAuth client
  credentials (`:client_id` / `:client_secret`) or a bearer token (`:token`).
  Previously the library relied on an interactive CLI login.
* **Connection IDs are UUIDs.** The old numeric authentication IDs no longer
  resolve.
* `async/4` became `async/5`: the action type is now explicit, since a
  fire-and-forget call is as likely to be a write as a search.
* Removed `ZapierSDK.CLI.Executor`, `ZapierSDK.CLI.Port`,
  `ZapierSDK.CLI.SystemCmd`, and `ZapierSDK.CLI.NDJSON`. Tests that mocked the
  executor with Mox should stub the transport with `Req.Test` instead.
* Removed `ZapierSDK.Apps.GitLab`; added `ZapierSDK.Apps.GoogleDrive`.
* `ZapierSDK.Error` types were replaced with HTTP-oriented ones. `:cli_not_found`,
  `:execution_failed`, and `:parse_error` are gone.
* `Action.type_to_cli_arg/1` became `Action.type_to_api/1`, and raises on an
  unknown type rather than silently producing an invalid request.

### Fixed

* **Every action returned zero results.** The CLI emits a single pretty-printed
  JSON envelope, but the library parsed its output as newline-delimited JSON
  and discarded every line that failed to decode — so a successful call
  produced `{:ok, %Result{count: 0}}` regardless of what came back.
* **Action failures were reported as success.** The `errors` array on a
  finished run was never inspected, so an expired connection looked like an
  empty result set. Failures now return a typed error, with
  `:connection_expired` broken out from `:action_failed`.
* **The documented install was the wrong package.** `zapier-sdk` on npm is an
  unrelated placeholder; the CLI is `@zapier/zapier-sdk-cli`.
* The CLI invocation used `--connection-id`, which the current CLI does not
  accept.
* App helpers referenced actions and input fields that do not exist:
  Slack's message body is `text` (not `message`) and a DM's recipient travels
  in `channel` (not `user`); Google Calendar searches use `event_v2` with
  `calendarid`/`start_time`/`end_time` (not `find_multiple_events` with
  `calendar_id`/`time_min`/`time_max`); Coda's app key is `CodaCLIAPI` and its
  actions are `rowList`/`rowSearch`/`rowCreateV2`.

### Added

* Automatic OAuth token caching and refresh, safe under concurrent callers.
* Cursor pagination, with `:max_items` and a lazy `stream/4`.
* ETS-cached app and action metadata resolution.
* Discovery helpers: `list_apps/1`, `list_actions/2`, `list_connections/1`.
  An unknown action key now reports the valid ones.
* A retry policy that retries only idempotent requests, never replays an
  action-run `POST`, and surfaces 429 with `:retry_after_ms` instead of
  sleeping inside the call.

## v0.1.0

Initial release.
