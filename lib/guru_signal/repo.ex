defmodule GuruSignal.Repo do
  use Ecto.Repo,
    otp_app: :guru_signal,
    adapter: Ecto.Adapters.Postgres
end
