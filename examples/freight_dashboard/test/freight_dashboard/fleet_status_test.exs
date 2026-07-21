defmodule FreightDashboard.FleetStatusTest do
  use ExUnit.Case, async: true

  @fleet [
    %{name: "Big Rig Alpha", status: "available", location: "Chicago Yard"},
    %{name: "Thunder Hauler", status: "on_route", location: "I-80, Nebraska"},
    %{name: "Midnight Express", status: "maintenance", location: "Denver Garage"}
  ]

  setup_all do
    Mace.Mock.install()
    :ok
  end

  describe "with legacy fleet status" do
    setup do
      Mace.put_config(
        :freight_dashboard,
        :fleet_status,
        FreightDashboard.FleetStatus.Legacy
      )
    end

    test "renders fleet as a plain list" do
      html =
        %{fleet: @fleet}
        |> FreightDashboard.FleetStatus.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "fleet-list"
      assert html =~ "Big Rig Alpha"
      assert html =~ "available"
      assert html =~ "Chicago Yard"
      assert html =~ "Thunder Hauler"
      assert html =~ "Midnight Express"
      refute html =~ "status-card"
    end
  end

  describe "with new fleet status" do
    setup do
      Mace.put_config(
        :freight_dashboard,
        :fleet_status,
        FreightDashboard.FleetStatus.New
      )
    end

    test "renders fleet as status cards" do
      html =
        %{fleet: @fleet}
        |> FreightDashboard.FleetStatus.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "status-card"
      assert html =~ "Big Rig Alpha"
      assert html =~ "Chicago Yard"
      assert html =~ "Thunder Hauler"
      assert html =~ "Midnight Express"
      assert html =~ "status-available"
      assert html =~ "status-on-route"
      assert html =~ "status-maintenance"
      refute html =~ "fleet-list"
    end
  end
end
