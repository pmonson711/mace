defmodule FreightDashboard.ShipmentTrackerTest do
  use ExUnit.Case, async: true

  @shipments [
    %{id: "CHI-LAX-001", origin: "Chicago", destination: "Los Angeles", status: "in_transit"},
    %{id: "NYC-MIA-002", origin: "New York", destination: "Miami", status: "delivered"},
    %{id: "SEA-PDX-003", origin: "Seattle", destination: "Portland", status: "pending"}
  ]

  setup_all do
    Mace.Mock.install()
    :ok
  end

  describe "with legacy tracker" do
    setup do
      Mace.put_config(
        :freight_dashboard,
        :shipment_tracker,
        FreightDashboard.ShipmentTracker.Legacy
      )
    end

    test "renders shipments in a table" do
      html =
        %{shipments: @shipments}
        |> FreightDashboard.ShipmentTracker.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ ~r/<table/
      assert html =~ "CHI-LAX-001"
      assert html =~ "NYC-MIA-002"
      assert html =~ "SEA-PDX-003"
      refute html =~ "progress-bar"
    end
  end

  describe "with new tracker" do
    setup do
      Mace.put_config(
        :freight_dashboard,
        :shipment_tracker,
        FreightDashboard.ShipmentTracker.New
      )
    end

    test "renders shipments as timeline cards" do
      html =
        %{shipments: @shipments}
        |> FreightDashboard.ShipmentTracker.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "shipment-card"
      assert html =~ "progress-bar"
      assert html =~ "CHI-LAX-001"
      assert html =~ "NYC-MIA-002"
      assert html =~ "SEA-PDX-003"
      refute html =~ ~r/<table/
    end
  end
end
