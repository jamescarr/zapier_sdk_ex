defmodule ZapierSDK.HTTP do
  @moduledoc """
  Thin transport layer over `Req` for the Zapier SDK API.

  Handles bearer-token injection, decoding Zapier's `{"data": _, "errors": _}`
  envelope, and mapping HTTP failures onto `ZapierSDK.Error`. Everything above
  this module works with decoded payloads and typed errors.
  """

  alias ZapierSDK.{Auth, Config, Error}

  @doc """
  Issue a request and unwrap the response envelope.

  Returns `{:ok, data, response}` on success so callers that care about the
  status (polling, which distinguishes 202 from 200) can inspect it.
  """
  @spec request(atom(), String.t(), keyword()) ::
          {:ok, term(), Req.Response.t()} | {:error, Error.t()}
  def request(method, path, opts \\ []) do
    with {:ok, token} <- Auth.token() do
      opts
      |> build(method, path, token)
      |> Req.request()
      |> handle_response()
    end
  end

  defp build(opts, method, path, token) do
    {req_opts, opts} = Keyword.split(opts, [:json, :params, :receive_timeout])

    [
      method: method,
      base_url: Config.api_base_url(),
      url: path,
      auth: {:bearer, token},
      receive_timeout: Keyword.get(opts, :timeout, 60_000),
      retry: &retry?/2,
      retry_delay: &retry_delay/1,
      max_retries: Config.max_retries()
    ]
    |> Keyword.merge(req_opts)
    |> Keyword.merge(Config.req_options())
    |> Req.new()
  end

  # Retrying is only safe for requests that can be replayed. Creating an action
  # run is a POST with real side effects — a retried "send Slack message" sends
  # it twice — so those failures are surfaced instead.
  defp retry?(request, response_or_error) do
    idempotent?(request.method) and transient?(response_or_error)
  end

  defp idempotent?(method), do: method in [:get, :head, :put, :delete]

  # 429 is deliberately excluded: Zapier's Retry-After can be tens of seconds,
  # and silently sleeping inside a call the caller thinks is bounded is worse
  # than handing back a :rate_limited error with the delay attached.
  defp transient?(%Req.Response{status: status}), do: status >= 500
  defp transient?(%Req.TransportError{}), do: true
  defp transient?(_), do: false

  defp retry_delay(attempt), do: min(200 * 2 ** attempt, 2_000)

  defp handle_response({:ok, %Req.Response{status: status} = resp}) when status in 200..299 do
    case resp.body do
      %{"data" => data} -> {:ok, data, resp}
      # A handful of endpoints answer with a bare body rather than an envelope.
      %{} = body -> {:ok, body, resp}
      body when is_list(body) -> {:ok, body, resp}
      _ -> {:error, Error.new(:invalid_response, "unexpected response body", details: resp.body)}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 401} = resp}) do
    # The token may have been revoked before its stated expiry; drop it so the
    # next attempt mints a fresh one instead of replaying a dead credential.
    Auth.invalidate()

    {:error,
     Error.new(:authentication_failed, "Zapier rejected the credentials (HTTP 401)",
       status: 401,
       details: resp.body
     )}
  end

  defp handle_response({:ok, %Req.Response{status: 404} = resp}) do
    {:error, Error.new(:http_error, "not found (HTTP 404)", status: 404, details: resp.body)}
  end

  defp handle_response({:ok, %Req.Response{status: 429} = resp}) do
    {:error,
     Error.new(:rate_limited, "rate limited by Zapier",
       status: 429,
       details: resp.body,
       retry_after_ms: retry_after_ms(resp)
     )}
  end

  defp handle_response({:ok, %Req.Response{status: status} = resp}) do
    {:error,
     Error.new(:http_error, "Zapier returned HTTP #{status}#{detail(resp.body)}",
       status: status,
       details: resp.body
     )}
  end

  defp handle_response({:error, reason}) do
    {:error, Error.new(:transport_error, "request to Zapier failed", details: reason)}
  end

  defp detail(%{"errors" => [%{"detail" => detail} | _]}) when is_binary(detail),
    do: ": #{detail}"

  defp detail(_), do: ""

  defp retry_after_ms(resp) do
    case Req.Response.get_header(resp, "retry-after") do
      [value | _] ->
        case Integer.parse(value) do
          {seconds, _} -> seconds * 1000
          :error -> nil
        end

      _ ->
        nil
    end
  end
end
