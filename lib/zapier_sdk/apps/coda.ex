defmodule ZapierSDK.Apps.Coda do
  @moduledoc """
  Convenience wrappers for Coda actions.

  Expects a `:coda` connection, or pass `connection:` to override:

      config :zapier_sdk, connections: [
        coda: {"CodaCLIAPI", "your-connection-uuid"}
      ]

  The app is addressed by its key `CodaCLIAPI` rather than a slug, because
  Coda's public slug has since been reassigned to `superhuman-docs` while the
  key stayed stable.

  ## Examples

      {:ok, rows} = ZapierSDK.Apps.Coda.list_rows(doc_id, table_id)
      {:ok, row}  = ZapierSDK.Apps.Coda.find_row(doc_id, table_id, "Status", "Open")
  """

  alias ZapierSDK.{Action, Error, Result}

  @default_conn :coda

  @doc "List rows in a table."
  @spec list_rows(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def list_rows(doc_id, table_id, opts \\ []) do
    run(Action.read("rowList", %{"documentId" => doc_id, "tableId" => table_id}), opts)
  end

  @doc "Find a row by matching a column against a value."
  @spec find_row(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def find_row(doc_id, table_id, column_id, value, opts \\ []) do
    inputs = %{
      "documentId" => doc_id,
      "tableId" => table_id,
      "columnId" => column_id,
      "searchValue" => value
    }

    run(Action.search("rowSearch", inputs), opts)
  end

  @doc """
  Create a row.

  `cells` maps column IDs to values and is passed through to Coda as-is.
  """
  @spec create_row(String.t(), String.t(), map(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def create_row(doc_id, table_id, cells, opts \\ []) do
    inputs = %{
      "documentId" => doc_id,
      "tableId" => table_id,
      "dynamic_properties" => cells
    }

    run(Action.write("rowCreateV2", inputs), opts)
  end

  defp run(action, opts) do
    ZapierSDK.run(Keyword.get(opts, :connection, @default_conn), action, opts)
  end
end
