defmodule FreightDashboard.FleetStatus.Legacy do
  @moduledoc """
  Legacy fleet status: renders a plain text list of vehicles.
  """
  use Phoenix.Component
  @behaviour FreightDashboard.FleetStatus

  attr :fleet, :list, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <ul class="fleet-list">
      <li :for={vehicle <- @fleet}>
        <strong>{vehicle.name}</strong> — {vehicle.status} ({vehicle.location})
      </li>
    </ul>
    """
  end
end
