defmodule JidoDelvetown.Settings.Console do
  @moduledoc "Reads and changes operator console settings."

  alias JidoDelvetown.Settings

  @themes ~w(system light dark)

  @spec themes() :: [String.t()]
  def themes, do: @themes

  @spec theme(keyword()) :: {:ok, String.t()} | {:error, term()}
  def theme(opts \\ []) do
    with {:ok, setting} <- Settings.fetch(:console_theme, opts) do
      {:ok, setting.value}
    end
  end

  @spec select_theme(String.t(), keyword()) :: {:ok, Settings.snapshot()} | {:error, term()}
  def select_theme(theme, opts \\ []) do
    opts = Keyword.put_new(opts, :source, "operator_console")
    Settings.update(%{console_theme: theme}, opts)
  end
end
