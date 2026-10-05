defmodule JidoDelvetown.Jido do
  @moduledoc "The named Jido instance that owns Delvetown agents."

  use Jido,
    otp_app: :jido_delvetown,
    namespace: "jido/delvetown",
    persistence: {Jido.Persistence.Ecto, repo: JidoDelvetown.Repo}
end
