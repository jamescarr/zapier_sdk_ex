defmodule ZapierSDK.Apps.GoogleDrive do
  @moduledoc """
  Convenience wrappers for Google Drive actions.

  Expects a `:drive` connection, or pass `connection:` to override:

      config :zapier_sdk, connections: [
        drive: {"google-drive", "your-connection-uuid"}
      ]

  ## Examples

      {:ok, result} = ZapierSDK.Apps.GoogleDrive.find_file("Q3 budget")
      {:ok, result} = ZapierSDK.Apps.GoogleDrive.find_folder("Design")
  """

  alias ZapierSDK.{Action, Error, Result}

  @default_conn :drive

  @doc """
  Find a file by title.

  ## Options

    * `:drive` — shared drive ID; defaults to My Drive
    * `:folder` — restrict the search to a folder ID
    * `:file_types` — filter by type, e.g. `"document"`
    * `:search_type` — how `title` is matched, e.g. `"exact"`
  """
  @spec find_file(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def find_file(title, opts \\ []) do
    run(Action.search("file_v2", file_inputs(title, opts)), opts)
  end

  @doc "Find a folder by title. Accepts the same options as `find_file/2`."
  @spec find_folder(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def find_folder(title, opts \\ []) do
    run(Action.search("folder_v2", file_inputs(title, opts)), opts)
  end

  @doc "Retrieve a file or folder by its Drive ID."
  @spec get_by_id(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def get_by_id(id, opts \\ []) do
    run(Action.search("file_or_folder_by_id", %{"id" => id}), opts)
  end

  @doc "Create a folder, optionally inside a parent folder."
  @spec create_folder(String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def create_folder(name, opts \\ []) do
    inputs =
      %{"folder_name" => name}
      |> maybe_put("drive", opts[:drive])
      |> maybe_put("folder", opts[:parent])

    run(Action.write("folder", inputs), opts)
  end

  defp file_inputs(title, opts) do
    %{"title" => title}
    |> maybe_put("drive", opts[:drive])
    |> maybe_put("folder", opts[:folder])
    |> maybe_put("file_types", opts[:file_types])
    |> maybe_put("search_type", opts[:search_type])
  end

  defp run(action, opts) do
    ZapierSDK.run(Keyword.get(opts, :connection, @default_conn), action, opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
