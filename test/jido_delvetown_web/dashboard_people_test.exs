defmodule JidoDelvetownWeb.DashboardPeopleTest do
  use ExUnit.Case, async: true

  alias JidoDelvetownWeb.DashboardPeople

  test "normalizes the bounded people snapshot" do
    inspection = %{
      people: %{
        counts: %{
          known: 3,
          friends: 1,
          followers: 2,
          following: 1,
          mutuals: 1,
          excluded: 1
        },
        records: [%{did: "did:plc:friend", friend?: true}],
        visible_count: 1,
        truncated?: true
      }
    }

    people = DashboardPeople.build(inspection)

    assert people.counts.known == 3
    assert people.counts.followers == 2
    assert people.records == [%{did: "did:plc:friend", friend?: true}]
    assert people.visible_count == 1
    assert people.truncated?
  end

  test "returns stable empty values when people inspection is unavailable" do
    assert DashboardPeople.build(%{}) == %{
             counts: %{
               known: 0,
               friends: 0,
               followers: 0,
               following: 0,
               mutuals: 0,
               excluded: 0
             },
             records: [],
             visible_count: 0,
             truncated?: false
           }
  end
end
