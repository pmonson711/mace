defmodule FreightDashboardWeb.DashboardLiveTest do
  use FreightDashboardWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "mounts and renders dashboard with legacy widgets by default", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Freight Command Center"
    assert html =~ "Active Shipments"
    assert html =~ "Fleet Status"
    assert html =~ "shipment-table"
    assert html =~ "fleet-list"
    assert html =~ "CHI-LAX-001"
    assert html =~ "Big Rig Alpha"
    assert html =~ "opencode"
  end

  test "flag manager shows current implementations", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "ShipmentTracker.Legacy"
    assert html =~ "FleetStatus.Legacy"
  end

  # This test does not use Mace because mace only intercepts
  # Application.get_env/fetch_env/get_all_env — not put_env. The dashboard's
  # toggle handler calls Application.put_env directly (it's production demo
  # code), so the mutation is real and global. try/after restores the
  # original config so other async tests don't see the pollution.
  test "toggling shipment tracker re-renders the widget", %{conn: conn} do
    original = Application.get_env(:freight_dashboard, :shipment_tracker)

    try do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "shipment-table"
      refute html =~ "shipment-timeline"

      html = view |> element(~s|button[phx-value-flag="shipment"]|) |> render_click()

      assert html =~ "ShipmentTracker.New"
      assert html =~ "shipment-timeline"
      refute html =~ "shipment-table"
    after
      Application.put_env(:freight_dashboard, :shipment_tracker, original)
    end
  end
end
