defmodule FreightDashboardWeb.FlagManagerLive do
  use FreightDashboardWeb, :live_component

  @impl true
  def update(_assigns, socket) do
    shipment_impl =
      Application.get_env(:freight_dashboard, :shipment_tracker,
        FreightDashboard.ShipmentTracker.Legacy
      )

    fleet_impl =
      Application.get_env(:freight_dashboard, :fleet_status,
        FreightDashboard.FleetStatus.Legacy
      )

    {:ok,
     assign(socket,
       shipment_impl: shipment_impl,
       fleet_impl: fleet_impl,
       shipment_default: FreightDashboard.ShipmentTracker.Legacy,
       fleet_default: FreightDashboard.FleetStatus.Legacy
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flag-manager">
      <h3>🔧 Feature Flags</h3>

      <div class="flag-row">
        <div class="flag-info">
          <strong>Shipment Tracker</strong>
          <span>Active: <code>{inspect(@shipment_impl)}</code></span>
          <span>Default: <code>{inspect(@shipment_default)}</code></span>
        </div>
        <button phx-click="toggle" phx-value-flag="shipment">
          Switch to {if @shipment_impl == FreightDashboard.ShipmentTracker.Legacy,
            do: "New",
            else: "Legacy"}
        </button>
      </div>

      <div class="flag-row">
        <div class="flag-info">
          <strong>Fleet Status</strong>
          <span>Active: <code>{inspect(@fleet_impl)}</code></span>
          <span>Default: <code>{inspect(@fleet_default)}</code></span>
        </div>
        <button phx-click="toggle" phx-value-flag="fleet">
          Switch to {if @fleet_impl == FreightDashboard.FleetStatus.Legacy, do: "New", else: "Legacy"}
        </button>
      </div>

      <p class="flag-note">
        Note: These toggles use <code>Application.put_env/3</code> for demo purposes.
        In production, use a database-backed feature flag system.
      </p>
    </div>
    """
  end
end
