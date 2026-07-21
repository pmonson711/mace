defmodule FreightDashboard.ShipmentTracker.New do
  @moduledoc """
  New shipment tracker: renders timeline cards with progress bars.
  """
  use Phoenix.Component
  @behaviour FreightDashboard.ShipmentTracker

  attr :shipments, :list, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="shipment-timeline">
      <div :for={shipment <- @shipments} class="shipment-card">
        <div class="truck-icon">🚚</div>
        <div class="shipment-info">
          <strong>{shipment.id}</strong>
          <span>{shipment.origin} → {shipment.destination}</span>
        </div>
        <div class="progress-bar">
          <div class={"progress-fill progress-#{shipment.status}"}></div>
        </div>
        <span class="status-badge">{shipment.status}</span>
      </div>
    </div>
    """
  end
end
