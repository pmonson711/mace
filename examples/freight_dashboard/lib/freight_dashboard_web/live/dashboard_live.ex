defmodule FreightDashboardWeb.DashboardLive do
  use FreightDashboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    shipments = [
      %{id: "CHI-LAX-001", origin: "Chicago", destination: "Los Angeles", status: "in_transit"},
      %{id: "NYC-MIA-002", origin: "New York", destination: "Miami", status: "delivered"},
      %{id: "SEA-PDX-003", origin: "Seattle", destination: "Portland", status: "pending"}
    ]

    fleet = [
      %{name: "Big Rig Alpha", status: "available", location: "Chicago Yard"},
      %{name: "Thunder Hauler", status: "on_route", location: "I-80, Nebraska"},
      %{name: "Midnight Express", status: "maintenance", location: "Denver Garage"}
    ]

    {:ok, assign(socket, shipments: shipments, fleet: fleet, refresh: 0)}
  end

  @impl true
  def handle_event("toggle", %{"flag" => "shipment"}, socket) do
    current =
      Application.get_env(:freight_dashboard, :shipment_tracker,
        FreightDashboard.ShipmentTracker.Legacy
      )

    new_impl =
      if current == FreightDashboard.ShipmentTracker.Legacy do
        FreightDashboard.ShipmentTracker.New
      else
        FreightDashboard.ShipmentTracker.Legacy
      end

    Application.put_env(:freight_dashboard, :shipment_tracker, new_impl)
    {:noreply, assign(socket, refresh: socket.assigns.refresh + 1)}
  end

  def handle_event("toggle", %{"flag" => "fleet"}, socket) do
    current =
      Application.get_env(:freight_dashboard, :fleet_status,
        FreightDashboard.FleetStatus.Legacy
      )

    new_impl =
      if current == FreightDashboard.FleetStatus.Legacy do
        FreightDashboard.FleetStatus.New
      else
        FreightDashboard.FleetStatus.Legacy
      end

    Application.put_env(:freight_dashboard, :fleet_status, new_impl)
    {:noreply, assign(socket, refresh: socket.assigns.refresh + 1)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <header class="dashboard-header">
        <h1>🚛 Freight Command Center</h1>
        <p class="subtitle">Feature-flagged dashboard demonstrating mace's expand/contract pattern</p>
      </header>

      <.live_component module={FreightDashboardWeb.FlagManagerLive} id="flag-manager" refresh={@refresh} />

      <div class="widgets">
        <section class="widget">
          <h2>📦 Active Shipments</h2>
          <FreightDashboard.ShipmentTracker.render shipments={@shipments} refresh={@refresh} />
        </section>

        <section class="widget">
          <h2>🚚 Fleet Status</h2>
          <FreightDashboard.FleetStatus.render fleet={@fleet} refresh={@refresh} />
        </section>
      </div>

      <footer class="dashboard-footer">
        <p>
          Vibe coded with <a href="https://github.com/anomalyco/opencode">opencode</a>
          (deepseek-v4-pro)
        </p>
      </footer>
    </div>
    """
  end
end
