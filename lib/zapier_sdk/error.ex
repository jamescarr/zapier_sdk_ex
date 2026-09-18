defmodule ZapierSDK.Error do
  @moduledoc """
  Typed errors returned by the SDK.

  Every public function returns `{:error, %ZapierSDK.Error{}}` rather than
  raising, so callers can match on `:type` and decide what is retryable.

  | Type | Meaning | Retryable |
  |---|---|---|
  | `:no_credentials` | Nothing configured to authenticate with | no |
  | `:authentication_failed` | Token exchange rejected, or the API returned 401 | no |
  | `:action_failed` | The run finished with errors from the integration | depends |
  | `:connection_expired` | The app connection needs to be reconnected | no |
  | `:app_not_found` / `:action_not_found` / `:connection_not_found` | Bad identifier | no |
  | `:rate_limited` | 429 from Zapier; see `:retry_after_ms` | yes |
  | `:timeout` | The run did not finish within the timeout | yes |
  | `:http_error` | Any other non-success status | depends |
  | `:transport_error` | The request never completed | yes |
  """

  defexception [:type, :message, :details, :status, :retry_after_ms]

  @type error_type ::
          :no_credentials
          | :authentication_failed
          | :action_failed
          | :connection_expired
          | :app_not_found
          | :action_not_found
          | :connection_not_found
          | :rate_limited
          | :timeout
          | :http_error
          | :transport_error
          | :invalid_response

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: term(),
          status: pos_integer() | nil,
          retry_after_ms: non_neg_integer() | nil
        }

  @doc false
  def new(type, message, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      details: Keyword.get(opts, :details),
      status: Keyword.get(opts, :status),
      retry_after_ms: Keyword.get(opts, :retry_after_ms)
    }
  end

  @doc false
  def no_credentials do
    new(
      :no_credentials,
      "no Zapier credentials configured. Set :client_id and :client_secret " <>
        "(or :token) under config :zapier_sdk, or export " <>
        "ZAPIER_CREDENTIALS_CLIENT_ID and ZAPIER_CREDENTIALS_CLIENT_SECRET"
    )
  end

  @doc false
  def timeout(ms, details \\ nil) do
    new(:timeout, "action did not complete within #{ms}ms", details: details)
  end

  @doc """
  Build an error from the `errors` array Zapier returns on a finished run.

  Connection-expiry is promoted to its own type because it is the one failure
  a caller can actually act on — the fix is reconnecting the app, not retrying.
  """
  @spec from_action_errors([map()]) :: t()
  def from_action_errors(errors) when is_list(errors) do
    message =
      errors
      |> Enum.map(fn e -> e["detail"] || e["title"] || "Unknown error" end)
      |> Enum.join("; ")

    type =
      if Enum.any?(errors, &(&1["code"] == "authentication_error")),
        do: :connection_expired,
        else: :action_failed

    new(type, message, details: errors)
  end

  @impl true
  def message(%__MODULE__{message: message}), do: message
end
