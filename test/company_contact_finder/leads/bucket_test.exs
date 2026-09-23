defmodule CompanyContactFinder.Leads.BucketTest do
  use ExUnit.Case, async: true

  import CompanyContactFinder.LeadStubs

  alias CompanyContactFinder.Leads.Bucket

  test "splits comma-separated industries and locations" do
    changeset =
      Bucket.changeset(%Bucket{}, bucket_attrs(%{"industries" => "Food, Beverages,, food"}))

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :industries) == ["Food", "Beverages", "food"]
    assert Ecto.Changeset.get_change(changeset, :locations) == ["Nairobi"]
  end

  test "requires name, target and service" do
    changeset = Bucket.changeset(%Bucket{}, %{})
    refute changeset.valid?
    assert Keyword.keys(changeset.errors) -- [:name, :target_description, :service] == []
  end

  test "rejects unknown company sizes and ignores blanks from the form" do
    refute Bucket.changeset(%Bucket{}, bucket_attrs(%{"company_sizes" => ["huge"]})).valid?

    changeset = Bucket.changeset(%Bucket{}, bucket_attrs(%{"company_sizes" => ["", "large"]}))
    assert Ecto.Changeset.get_change(changeset, :company_sizes) == ["large"]
  end

  test "criteria_changed_at moves only when scoring criteria change" do
    existing = %Bucket{
      id: 1,
      name: "Old",
      target_description: "Food",
      service: "Barcodes",
      criteria_changed_at: ~U[2026-01-01 00:00:00Z]
    }

    renamed = Bucket.changeset(existing, %{"name" => "New name"})
    refute Map.has_key?(renamed.changes, :criteria_changed_at)

    retargeted = Bucket.changeset(existing, %{"target_description" => "Drinks"})
    assert %DateTime{} = retargeted.changes.criteria_changed_at
  end
end
