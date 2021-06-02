defmodule TaskBunny do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias TaskBunny.Status

  @spec start(atom, term) :: {:ok, pid} | {:ok, pid, any} | {:error, term}
  def start(_type, _args) do
    register_metrics()

    # Define workers and child supervisors to be supervised
    children = [
      %{id: TaskBunny.Supervisor, start: {TaskBunny.Supervisor, :start_link, []}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: TaskBunny)
  end

  defp register_metrics do
    if Code.ensure_loaded(Wobserver) == {:module, Wobserver} do
      Wobserver.register(:page, {"Task Bunny", :taskbunny, &Status.page/0})
      Wobserver.register(:metric, [&Status.metrics/0])
    end
  end
end
