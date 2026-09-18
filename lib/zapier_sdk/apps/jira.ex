defmodule ZapierSDK.Apps.Jira do
  @moduledoc """
  Convenience wrappers for Jira Software Cloud actions.

  Expects a `:jira` connection, or pass `connection:` to override:

      config :zapier_sdk, connections: [
        jira: {"jira-software-cloud", "your-connection-uuid"}
      ]

  ## Examples

      # Search with JQL
      {:ok, result} = ZapierSDK.Apps.Jira.search_jql("assignee = currentUser()")

      # Find a specific issue
      {:ok, result} = ZapierSDK.Apps.Jira.find_issue("STAFF-2899")

      # Create an issue
      {:ok, result} = ZapierSDK.Apps.Jira.create_issue("STAFF", "Task", "Fix the thing",
        description: "It's broken"
      )
  """

  alias ZapierSDK.{Action, Result, Error}

  @default_conn :jira

  @doc "Search issues via JQL. Uses `issues_jql` (plural) to avoid restricted action errors."
  @spec search_jql(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def search_jql(jql, opts \\ []) do
    conn = Keyword.get(opts, :connection, @default_conn)
    max_results = Keyword.get(opts, :max_results, "25")

    ZapierSDK.run(
      conn,
      Action.search("issues_jql", %{
        "jql" => jql,
        "max_results" => to_string(max_results)
      }),
      opts
    )
  end

  @doc "Find an issue by key."
  @spec find_issue(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def find_issue(key, opts \\ []) do
    conn = Keyword.get(opts, :connection, @default_conn)

    ZapierSDK.run(
      conn,
      Action.search("issue_key", %{
        "issue_key" => key
      }),
      opts
    )
  end

  @doc "Find an issue by summary or key."
  @spec find_by_summary(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def find_by_summary(search_value, opts \\ []) do
    conn = Keyword.get(opts, :connection, @default_conn)

    ZapierSDK.run(
      conn,
      Action.search("issue", %{
        "search_value" => search_value
      }),
      opts
    )
  end

  @doc "Create a new Jira issue."
  @spec create_issue(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def create_issue(project_key, issue_type, summary, opts \\ []) do
    conn = Keyword.get(opts, :connection, @default_conn)

    inputs =
      %{
        "project" => project_key,
        "issue_type" => issue_type,
        "summary" => summary
      }
      |> maybe_put("description", Keyword.get(opts, :description))
      |> maybe_put("priority", Keyword.get(opts, :priority))
      |> maybe_put("assignee", Keyword.get(opts, :assignee))
      |> maybe_put("labels", Keyword.get(opts, :labels))

    ZapierSDK.run(conn, Action.write("create_issue", inputs), opts)
  end

  @doc "Add a comment to an issue."
  @spec add_comment(String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def add_comment(issue_key, body, opts \\ []) do
    conn = Keyword.get(opts, :connection, @default_conn)

    ZapierSDK.run(
      conn,
      Action.write("add_comment", %{
        "issue_key" => issue_key,
        "body" => body
      }),
      opts
    )
  end

  @doc "Get my assigned, open tickets."
  @spec my_open_issues(keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def my_open_issues(opts \\ []) do
    search_jql("assignee = currentUser() AND status != Done ORDER BY updated DESC", opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
