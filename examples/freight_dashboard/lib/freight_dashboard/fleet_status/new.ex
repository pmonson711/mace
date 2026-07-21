defmodule FreightDashboard.FleetStatus.New do
  @moduledoc """
  New fleet status: renders color-coded status cards with location badges.
  """
  use Phoenix.Component
  @behaviour FreightDashboard.FleetStatus

  attr :fleet, :list, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fleet-cards">
      <div :for={vehicle <- @fleet} class="status-card">
        <div class="vehicle-icon">🚛</div>
        <div class="vehicle-info">
          <strong>{vehicle.name}</strong>
          <span class={[
            "status-badge",
            case vehicle.status do
              "available" -> "status-available"
              "on_route" -> "status-on-route"
              "maintenance" -> "status-maintenance"
              _ -> "status-unknown"
            end
          ]}>
            {vehicle.status}
          </span>
        </div>
        <div class="location-badge">
          📍 {vehicle.location}
        </div>
      </div>
    </div>
    """
  end
end
