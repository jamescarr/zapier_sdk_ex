defmodule ZapierSDK.Apps.Slack do
  @moduledoc """
  Convenience wrappers for Slack actions.

  Expects a `:slack` connection, or pass `connection:` to override:

      config :zapier_sdk, connections: [
        slack: {"slack", "your-connection-uuid"}
      ]

  ## Examples

      {:ok, result} = ZapierSDK.Apps.Slack.search("deployment failed")
      {:ok, _} = ZapierSDK.Apps.Slack.send_message("#general", "Hello from Elixir")
  """

  alias ZapierSDK.{Action, Error, Result}

  @default_conn :slack

  @doc "Find messages matching a query."
  @spec search(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def search(query, opts \\ []) do
    inputs =
      %{"query" => query}
      |> maybe_put("sort_by", opts[:sort_by])
      |> maybe_put("sort_dir", opts[:sort_dir])

    run(Action.search("message", inputs), opts)
  end

  @doc """
  Post a message to a channel.

  Pass `thread_ts:` to reply in a thread.
  """
  @spec send_message(String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def send_message(channel, text, opts \\ []) do
    inputs =
      %{"channel" => channel, "text" => text}
      |> maybe_put("thread_ts", opts[:thread_ts])
      |> maybe_put("as_bot", opts[:as_bot])
      |> maybe_put("username", opts[:username])

    run(Action.write("channel_message", inputs), opts)
  end

  @doc """
  Send a direct message.

  Slack models a DM as a conversation, so `user` is the recipient's handle or
  user ID and travels in the `channel` field.
  """
  @spec send_dm(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def send_dm(user, text, opts \\ []) do
    run(Action.write("direct_message", %{"channel" => user, "text" => text}), opts)
  end

  @doc "Find a user by email address."
  @spec find_user_by_email(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def find_user_by_email(email, opts \\ []) do
    run(Action.search("user_by_email", %{"email" => email}), opts)
  end

  @doc "Set your Slack status."
  @spec set_status(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def set_status(text, emoji \\ ":speech_balloon:", opts \\ []) do
    run(
      Action.write("set_status", %{"status_text" => text, "status_emoji" => emoji}),
      opts
    )
  end

  defp run(action, opts) do
    ZapierSDK.run(Keyword.get(opts, :connection, @default_conn), action, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
