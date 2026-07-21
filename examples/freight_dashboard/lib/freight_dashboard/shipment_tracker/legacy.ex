defmodule FreightDashboard.ShipmentTracker.Legacy do
  @moduledoc """
  Legacy shipment tracker: renders a plain HTML table.
  """
  use Phoenix.Component
  @behaviour FreightDashboard.ShipmentTracker

  attr :shipments, :list, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <table class="shipment-table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Origin</th>
          <th>Destination</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={shipment <- @shipments}>
          <td>{shipment.id}</td>
          <td>{shipment.origin}</td>
          <td>{shipment.destination}</td>
          <td>{shipment.status}</td>
        </tr>
      </tbody>
    </table>
    """
  end
end
