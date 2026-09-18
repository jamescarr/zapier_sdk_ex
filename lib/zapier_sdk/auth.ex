defmodule ZapierSDK.Auth do
  @moduledoc """
  Supplies bearer tokens, refreshing them before they expire.

  Started as part of the `:zapier_sdk` supervision tree. Callers should use
  `token/0`; the exchange itself is an implementation detail.

  Concurrency matters here: `ZapierSDK.run_many/2` can start dozens of actions
  at once, and a naive cache would let every one of them mint its own token on
  a cold start. The exchange therefore runs inside the GenServer, so simultaneous
  callers queue behind a single in-flight request and share its result.
  """

  use GenServer

  alias ZapierSDK.{Config, Error}

  # Refresh slightly early so a token can't expire in flight.
  @expiry_buffer_ms 60_000

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Return a bearer token, minting or refreshing one if necessary.

  Static tokens are returned as-is. Client credentials are exchanged on first
  use and cached until shortly before they expire.
  """
  @spec token(GenServer.server(), timeout()) :: {:ok, String.t()} | {:error, Error.t()}
  def token(server \\ __MODULE__, timeout \\ 30_000) do
    case Config.credentials() do
      {:ok, {:token, token}} -> {:ok, token}
      {:ok, {:client_credentials, id, secret}} -> exchange(server, id, secret, timeout)
      {:error, :no_credentials} -> {:error, Error.no_credentials()}
    end
  end

  @doc """
  Drop any cached token, forcing the next call to mint a fresh one.

  Called automatically when the API rejects a token with 401, which covers the
  case where a token is revoked server-side before its stated expiry.
  """
  @spec invalidate(GenServer.server()) :: :ok
  def invalidate(server \\ __MODULE__), do: GenServer.cast(server, :invalidate)

  defp exchange(server, id, secret, timeout) do
    GenServer.call(server, {:token, id, secret}, timeout)
  catch
    :exit, {:timeout, _} ->
      {:error, Error.new(:authentication_failed, "timed out waiting for a token")}
  end

  @impl true
  def init(_opts), do: {:ok, %{token: nil, expires_at: nil, key: nil}}

  @impl true
  def handle_call({:token, id, secret}, _from, state) do
    key = {id, secret}

    if valid?(state, key) do
      {:reply, {:ok, state.token}, state}
    else
      case request_token(id, secret) do
        {:ok, token, expires_in} ->
          expires_at = System.monotonic_time(:millisecond) + expires_in * 1000
          {:reply, {:ok, token}, %{token: token, expires_at: expires_at, key: key}}

        {:error, %Error{} = error} ->
          {:reply, {:error, error}, %{state | token: nil, expires_at: nil}}
      end
    end
  end

  @impl true
  def handle_cast(:invalidate, state) do
    {:noreply, %{state | token: nil, expires_at: nil}}
  end

  defp valid?(%{token: nil}, _key), do: false
  defp valid?(%{key: key}, other) when key != other, do: false

  defp valid?(%{expires_at: expires_at}, _key) do
    System.monotonic_time(:millisecond) + @expiry_buffer_ms < expires_at
  end

  defp request_token(client_id, client_secret) do
    form = [
      grant_type: "client_credentials",
      client_id: client_id,
      client_secret: client_secret,
      scope: Config.scope(),
      audience: Config.audience()
    ]

    [url: Config.token_url(), form: form, receive_timeout: 30_000]
    |> Keyword.merge(Config.req_options())
    |> Req.new()
    |> Req.post()
    |> handle_token_response()
  end

  defp handle_token_response({:ok, %Req.Response{status: 200, body: body}})
       when is_map(body) do
    case body do
      %{"access_token" => token} when is_binary(token) ->
        {:ok, token, body["expires_in"] || 3600}

      _ ->
        {:error,
         Error.new(:authentication_failed, "token response had no access_token", details: body)}
    end
  end

  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error,
     Error.new(:authentication_failed, "client credentials exchange failed with HTTP #{status}",
       status: status,
       details: body
     )}
  end

  defp handle_token_response({:error, reason}) do
    {:error,
     Error.new(:transport_error, "could not reach the Zapier token endpoint", details: reason)}
  end
end
