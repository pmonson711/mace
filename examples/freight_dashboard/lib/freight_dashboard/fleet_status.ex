defmodule FreightDashboard.FleetStatus do
  @moduledoc """
  Dispatches to the configured fleet status implementation.
  """
  use Phoenix.Component

  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  attr :fleet, :list, required: true, doc: "List of vehicle maps"
  attr :refresh, :any, default: 0

  def render(assigns) do
    impl =
      Application.get_env(
        :freight_dashboard,
        :fleet_status,
        FreightDashboard.FleetStatus.Legacy
      )

    impl.render(assigns)
  end
end
