defmodule ZapierSDK.Config do
  @moduledoc """
  Resolves SDK configuration from application config and the environment.

  Application config always wins; environment variables are the fallback so
  the same release can be pointed at a different account without a rebuild.

      config :zapier_sdk,
        client_id: System.get_env("ZAPIER_CREDENTIALS_CLIENT_ID"),
        client_secret: System.get_env("ZAPIER_CREDENTIALS_CLIENT_SECRET")

  ## Credentials

  Two mechanisms are supported, matching the official SDK:

  * **Client credentials** (`:client_id` + `:client_secret`) — the
    server-to-server OAuth flow. Preferred for anything long-running: tokens
    are fetched and refreshed automatically.
  * **Static token** (`:token`) — a bearer token you already hold. Useful for
    short-lived scripts and tests. Never refreshed.
  """

  @api_base "https://sdkapi.zapier.com"
  @auth_base "https://zapier.com"
  @default_scope "external"
  @default_audience "zapier.com"

  @doc "Base URL for the SDK API (`sdkapi.zapier.com`)."
  @spec api_base_url() :: String.t()
  def api_base_url do
    get(:api_base_url, "ZAPIER_BASE_URL_API") || @api_base
  end

  @doc "Base URL used to mint OAuth tokens."
  @spec auth_base_url() :: String.t()
  def auth_base_url do
    get(:auth_base_url, "ZAPIER_CREDENTIALS_BASE_URL") || @auth_base
  end

  @doc "Full URL of the OAuth token endpoint."
  @spec token_url() :: String.t()
  def token_url, do: auth_base_url() |> String.trim_trailing("/") |> Kernel.<>("/oauth/token/")

  @doc "OAuth scope requested during the client-credentials exchange."
  @spec scope() :: String.t()
  def scope, do: get(:scope, "ZAPIER_CREDENTIALS_SCOPE") || @default_scope

  @doc false
  @spec audience() :: String.t()
  def audience, do: get(:audience, "ZAPIER_CREDENTIALS_AUDIENCE") || @default_audience

  @doc """
  Resolve the configured credentials.

  Returns `{:ok, {:client_credentials, id, secret}}`, `{:ok, {:token, token}}`,
  or `{:error, :no_credentials}`.
  """
  @spec credentials() ::
          {:ok, {:client_credentials, String.t(), String.t()} | {:token, String.t()}}
          | {:error, :no_credentials}
  def credentials do
    client_id = get(:client_id, "ZAPIER_CREDENTIALS_CLIENT_ID")
    client_secret = get(:client_secret, "ZAPIER_CREDENTIALS_CLIENT_SECRET")
    token = get(:token, "ZAPIER_CREDENTIALS")

    cond do
      is_binary(client_id) and is_binary(client_secret) ->
        {:ok, {:client_credentials, client_id, client_secret}}

      is_binary(token) ->
        {:ok, {:token, token}}

      true ->
        {:error, :no_credentials}
    end
  end

  @doc "How long to wait for an action run to finish, in milliseconds."
  @spec action_timeout() :: pos_integer()
  def action_timeout, do: Application.get_env(:zapier_sdk, :action_timeout, 180_000)

  @doc "Default number of items requested per page."
  @spec page_size() :: pos_integer()
  def page_size, do: Application.get_env(:zapier_sdk, :page_size, 100)

  @doc """
  How many times to retry a retryable request.

  Only idempotent requests that fail with a transport error or a 5xx are
  retried; see `ZapierSDK.HTTP` for why 429 and `POST` are excluded.
  """
  @spec max_retries() :: non_neg_integer()
  def max_retries, do: Application.get_env(:zapier_sdk, :max_retries, 3)

  @doc """
  Extra options merged into every `Req` request.

  Tests use this to install a stub without touching the network:

      config :zapier_sdk, req_options: [plug: {Req.Test, ZapierSDK}]
  """
  @spec req_options() :: keyword()
  def req_options, do: Application.get_env(:zapier_sdk, :req_options, [])

  @doc "Named connections registered in application config."
  @spec connections() :: keyword()
  def connections, do: Application.get_env(:zapier_sdk, :connections, [])

  defp get(key, env_var) do
    case Application.get_env(:zapier_sdk, key) do
      nil -> System.get_env(env_var)
      value -> value
    end
  end
end
