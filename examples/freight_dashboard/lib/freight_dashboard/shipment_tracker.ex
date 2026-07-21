defmodule FreightDashboard.ShipmentTracker do
  @moduledoc """
  Dispatches to the configured shipment tracker implementation.

  Reads `Application.get_env(:freight_dashboard, :shipment_tracker)` at
  render time to decide which implementation to use.
  """
  use Phoenix.Component

  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  attr :shipments, :list, required: true, doc: "List of shipment maps"
  attr :refresh, :any, default: 0

  def render(assigns) do
    impl =
      Application.get_env(
        :freight_dashboard,
        :shipment_tracker,
        FreightDashboard.ShipmentTracker.Legacy
      )

    impl.render(assigns)
  end
end
